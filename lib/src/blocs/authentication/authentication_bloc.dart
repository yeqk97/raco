import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:bloc/bloc.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:oauth2/oauth2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:raco/flutter_datetime_picker-1.2.8-with-ca/src/date_format.dart';
import 'package:raco/src/blocs/loading_text/loading_text.dart';
import 'package:raco/src/data/dme.dart';
import 'package:raco/src/data/dme.dart' as prefix0;
import 'package:raco/src/models/custom_downloads.dart';
import 'package:raco/src/models/custom_events.dart';
import 'package:raco/src/models/custom_grades.dart';
import 'package:raco/src/models/db_helpers/attachment_helper.dart';
import 'package:raco/src/models/db_helpers/custom_event_helper.dart';
import 'package:raco/src/models/db_helpers/custom_grade_helper.dart';
import 'package:raco/src/models/db_helpers/event_helper.dart';
import 'package:raco/src/models/db_helpers/exam_helper.dart';
import 'package:raco/src/models/db_helpers/lab_image_helper.dart';
import 'package:raco/src/models/db_helpers/news_helper.dart';
import 'package:raco/src/models/db_helpers/notice_helper.dart';
import 'package:raco/src/models/db_helpers/schedule_helper.dart';
import 'package:raco/src/models/db_helpers/subject_helper.dart';
import 'package:raco/src/models/db_helpers/user_helper.dart';
import 'package:raco/src/models/requisits.dart';
import 'package:raco/src/resources/authentication_data.dart';
import 'package:raco/src/resources/global_translations.dart';
import 'package:raco/src/repositories/user_repository.dart';
import 'package:raco/src/blocs/authentication/authentication.dart';
import 'package:raco/src/repositories/repositories.dart';
import 'package:http/http.dart' as http;
import 'package:raco/src/models/models.dart';
import 'package:flutter/painting.dart';
import 'package:raco/src/utils/file_names.dart';
import 'package:raco/src/utils/keys.dart';
import 'package:raco/src/utils/read_write_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class AuthenticationBloc
    extends Bloc<AuthenticationEvent, AuthenticationState> {
  final LoadingTextBloc loadingTextBloc;
  AuthenticationBloc({
    @required this.loadingTextBloc,
  }) : assert(loadingTextBloc != null);

  @override
  AuthenticationState get initialState => AuthenticationUninitializedState();

  @override
  Stream<AuthenticationState> mapEventToState(
    AuthenticationEvent event,
  ) async* {
    if (event is AppStartedEvent) {
      bool hasCredentials = await user.hasCredentials();

      if (hasCredentials) {
        yield AuthenticationLoadingState();
        await _loadData();
        Dme().lastUpdate = await user.readFromPreferences(Keys.LAST_UPDATE);
        yield AuthenticationAuthenticatedState();
      } else {
        yield AuthenticationUnauthenticatedState();
      }
    }

    if (event is LoggedInEvent) {
      yield AuthenticationLoadingState();
      bool firsLogin = !await user.hasCredentials();
      await user.persistCredentials(event.credentials);
      try {
        if (!firsLogin) {
          Credentials c = await user.getCredentials();
          if(c.isExpired) {
            c = await c.refresh(identifier: AuthenticationData.identifier,secret: AuthenticationData.secret,);
            await user.persistCredentials(c);
          }
        }
        await _downloadData(firsLogin);
        String u = DateTime.now().toIso8601String();
        Dme().lastUpdate = u;
        user.writeToPreferences(Keys.LAST_UPDATE, u);
        yield AuthenticationAuthenticatedState();
      }catch(e) {
        loadingTextBloc
            .dispatch(LoadTextEvent(text: allTranslations.text('error_loading')));
        await Future.delayed(Duration(seconds:2));
        if (firsLogin) {
          if (await user.hasCredentials()) {
            //Clear image cache to update avatar
            imageCache.clear();
            await user.deleteCredentials();
          }
          SharedPreferences preferences = await SharedPreferences.getInstance();
          preferences.clear();
          var dir = await getApplicationDocumentsDirectory();
          List<FileSystemEntity> _files;
          _files = dir.listSync(recursive: true, followLinks: false);
          for (FileSystemEntity f in _files) {
            if (!f.path.contains('flutter_assets')) {
              f.deleteSync(recursive: false);
            }
          }
          await dbRepository.closeDB();
          await dbRepository.deleteDB();
          yield AuthenticationUnauthenticatedState();
        } else {
          yield AuthenticationAuthenticatedState();
        }

      }
    }

    if (event is LoggedOutEvent) {
      yield AuthenticationLoadingState();
      loadingTextBloc.dispatch(
          LoadTextEvent(text: allTranslations.text('clossing_loading')));
      if (await user.hasCredentials()) {
        //Clear image cache to update avatar
        imageCache.clear();
        await user.deleteCredentials();
      }
      SharedPreferences preferences = await SharedPreferences.getInstance();
      preferences.clear();
      Directory dir = await getApplicationDocumentsDirectory();
      List<FileSystemEntity> _files;
      _files = dir.listSync(recursive: true, followLinks: false);
      for (FileSystemEntity f in _files) {
        if (!f.path.contains('flutter_assets')) {
          f.deleteSync(recursive: false);
        }
      }
      await dbRepository.closeDB();
      await dbRepository.deleteDB();
      yield AuthenticationUnauthenticatedState();
    }
  }

  Future<void> _loadData() async {

    Dme().bpersonal = await user.readFromPreferences('personal_info') == 'true' ? true : false;
    Dme().bschedule = await user.readFromPreferences('schedule') == 'true' ? true : false;
    Dme().bnotices = await user.readFromPreferences('notices') == 'true' ? true : false;
    Dme().bevents = await user.readFromPreferences('events') == 'true' ? true : false;
    Dme().bnews = await user.readFromPreferences('news') == 'true' ? true : false;
    Dme().bsubjects = await user.readFromPreferences('subjects') == 'true' ? true : false;
    Dme().blabs = await user.readFromPreferences('labs') == 'true' ? true : false;

    String accessToken = await user.getAccessToken();
    String lang = await user.getPreferredLanguage();
    if (lang == '') {
      await user.setPreferredLanguage(allTranslations.currentLanguage);
      lang = allTranslations.currentLanguage;
    }
    RacoRepository rr = new RacoRepository(
        racoApiClient: RacoApiClient(
            httpClient: http.Client(), accessToken: accessToken, lang: lang));
    await dbRepository.openDB();

    //load personal information
    loadingTextBloc.dispatch(
        LoadTextEvent(text: allTranslations.text('personal_info_loading')));

    //singleton data object
    Dme dme = Dme();
    //read data from local files

    /*Me me = Me.fromJson(
        jsonDecode(await ReadWriteFile().readStringFromFile(FileNames.JO)));*/

    if (await user.readFromPreferences('personal_info') == 'true') {
      //Clear image cache to update avatar
      imageCache.clear();
      String imgPath = await rr.getImage();

      Me me = await rr.getMe();
      UserHelper meHelper = UserHelper.fromMe(me, imgPath);
      await dbRepository.cleanUserTable();
      await dbRepository.insertMeHelper(meHelper);

      //singleton data object
      Dme dme = Dme();
      dme.imgPath = imgPath;
      dme.username = me.username;
      dme.nom = me.nom;
      dme.cognoms = me.cognoms;
      dme.email = me.email;

    } else {
      UserHelper userHelper = await dbRepository.getMeHelper();
      Me me = Me.fromHelper(userHelper);

      dme.imgPath = userHelper.avatarPath;
      dme.username = me.username;
      dme.nom = me.nom;
      dme.cognoms = me.cognoms;
      dme.email = me.email;
    }


    //Load schedule information
    loadingTextBloc.dispatch(
        LoadTextEvent(text: allTranslations.text('schedule_loading')));

    if (await user.readFromPreferences('schedule') == 'true') {
        try {
          Classes classes = await rr.getClasses();
          classes.results.forEach((cl) async {
            await dbRepository.insertScheduleHelper(ScheduleHelper.fromClasse(cl, Dme().username));
          });
          _fillSchedule(classes);
        }catch (e) {
          /*    Classes classes = Classes.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.CLASSES)));*/
          List<ScheduleHelper> schedules = await dbRepository.getAllScheduleHelper();
          List<Classe> classeList = List();
          schedules.forEach((sch) {
            classeList.add(Classe.fromScheduleHelper(sch));
          });
          Classes classes = Classes(schedules.length, classeList);
          _fillSchedule(classes);
        }
    } else {
/*    Classes classes = Classes.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.CLASSES)));*/
      List<ScheduleHelper> schedules = await dbRepository.getAllScheduleHelper();
      List<Classe> classeList = List();
      schedules.forEach((sch) {
        classeList.add(Classe.fromScheduleHelper(sch));
      });
      Classes classes = Classes(schedules.length, classeList);
      _fillSchedule(classes);
    }


    //Load notices information
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('notices_loading')));

    if (await user.readFromPreferences('notices') == 'true') {
      try {
        Avisos avisos = await rr.getAvisos();
        dbRepository.cleanAttachmentHelperTable();
        dbRepository.cleanNoticeHelperTalbe();
        avisos.results.forEach((a) async {
          await dbRepository.insertNoticeHelper(NoticeHelper.fromAvis(a, Dme().username));
          a.adjunts.forEach((adj) async {
            await dbRepository.insertAttachmentHelper(AttachmentHelper.fromAdjunt(adj, a.id));
          });
        });
        dme.avisos = avisos;
      }catch (e) {
        /*    Avisos avisos = Avisos.fromJson(
        jsonDecode(await ReadWriteFile().readStringFromFile(FileNames.AVISOS)));*/
        List<NoticeHelper> noticeHelperList = await dbRepository.getAllNoticeHelper();
        List<Avis> avisList = List();
        noticeHelperList.forEach((n) async{
          List<AttachmentHelper> attachmentHelperList = await dbRepository.getAttachmentHelperByNoticeId(n.id);
          List<Adjunt> adjuntList = List();
          attachmentHelperList.forEach((at) {
            adjuntList.add(Adjunt.fromAttachmentHelper(at));
          });
          avisList.add(Avis.fromNoticeHelper(n, adjuntList));
        });
        dme.avisos = Avisos(avisList.length, avisList);

      }
    } else {
      /*    Avisos avisos = Avisos.fromJson(
        jsonDecode(await ReadWriteFile().readStringFromFile(FileNames.AVISOS)));*/
      List<NoticeHelper> noticeHelperList = await dbRepository.getAllNoticeHelper();
      List<Avis> avisList = List();
      noticeHelperList.forEach((n) async{
        List<AttachmentHelper> attachmentHelperList = await dbRepository.getAttachmentHelperByNoticeId(n.id);
        List<Adjunt> adjuntList = List();
        attachmentHelperList.forEach((at) {
          adjuntList.add(Adjunt.fromAttachmentHelper(at));
        });
        avisList.add(Avis.fromNoticeHelper(n, adjuntList));
      });
      dme.avisos = Avisos(avisList.length, avisList);
    }


    //Load events
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('events_loading')));

    if (await user.readFromPreferences('events') == 'true') {
      try{
        Events eventstt = await rr.getEvents();
        dbRepository.cleanEventHelperTable();
        eventstt.results.forEach((e) async {
          await dbRepository.insertEventHelper(EventHelper.fromEvent(e));
        });
        dme.events = eventstt;

        //Semester to obtain exams information
        Quadrimestre actual = await rr.getQuadrimestreActual();
        //Get exams
        Examens examens = await rr.getExamens(actual);
        dbRepository.cleanExamTable();
        examens.results.forEach((e) async {
          await dbRepository.insertExamtHelper(ExamHelper.fromExamen(e, Dme().username));
        });
        dme.examens = examens;

      }catch(e) {
        /*    Events events = Events.fromJson(
        jsonDecode(await ReadWriteFile().readStringFromFile(FileNames.EVENTS)));*/
        List<EventHelper> eventHelperList = await dbRepository.getAllEventHelper();
        List<Event> eventList = List();
        eventHelperList.forEach((e) {
          eventList.add(Event.fromEventHelper(e));
        });
        dme.events = Events(eventList.length, eventList);

        /*   Examens examens = Examens.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.EXAMENS)));*/
        List<ExamHelper> examHelperList = await dbRepository.getAllExamHelper();
        List<Examen> examenList = List();
        examHelperList.forEach((e) {
          examenList.add(Examen.fromExamHelper(e));
        });
        dme.examens = Examens(examenList.length, examenList);
      }
    } else {
      /*    Events events = Events.fromJson(
        jsonDecode(await ReadWriteFile().readStringFromFile(FileNames.EVENTS)));*/
      List<EventHelper> eventHelperList = await dbRepository.getAllEventHelper();
      List<Event> eventList = List();
      eventHelperList.forEach((e) {
        eventList.add(Event.fromEventHelper(e));
      });
      dme.events = Events(eventList.length, eventList);

      /*   Examens examens = Examens.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.EXAMENS)));*/
      List<ExamHelper> examHelperList = await dbRepository.getAllExamHelper();
      List<Examen> examenList = List();
      examHelperList.forEach((e) {
        examenList.add(Examen.fromExamHelper(e));
      });
      dme.examens = Examens(examenList.length, examenList);
    }


    //Load news
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('news_loading')));

    if (await user.readFromPreferences('news') == 'true') {
      try {
        Noticies noticies = await rr.getNoticies();
        dbRepository.cleanNewsHelperTable();
        noticies.results.forEach((n) async {
          await dbRepository.insertNewsHelper(NewsHelper.fromNoticia(n));
        });
        dme.noticies = noticies;
      }catch (e) {
        /*    Noticies noticies = Noticies.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.NOTICIES)));*/
        List<NewsHelper> newsHelperList = await dbRepository.getAllNewsHelper();
        List<Noticia> noticiaList = List();
        newsHelperList.forEach((nh) {
          noticiaList.add(Noticia.fromNewsHelper(nh));
        });
        Dme().noticies = Noticies(noticiaList.length, noticiaList);
      }
    } else {
      /*    Noticies noticies = Noticies.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.NOTICIES)));*/
      List<NewsHelper> newsHelperList = await dbRepository.getAllNewsHelper();
      List<Noticia> noticiaList = List();
      newsHelperList.forEach((nh) {
        noticiaList.add(Noticia.fromNewsHelper(nh));
      });
      Dme().noticies = Noticies(noticiaList.length, noticiaList);
    }



    //Load subjects information
    loadingTextBloc.dispatch(
        LoadTextEvent(text: allTranslations.text('subjects_loading')));

    if (await user.readFromPreferences('subjects') == 'true') {
      try{
        //Subjects information
        loadingTextBloc.dispatch(
            LoadTextEvent(text: allTranslations.text('subjects_loading')));
        Assignatures assignatures = await rr.getAssignatures();
        assignatures.results.forEach((a) async {
          await dbRepository.insertSubjectHelper(SubjectHelper.fromAssignatura(a, Dme().username));
        });
        dme.assignatures = assignatures;
        _assignColor(assignatures, false);
/*    await ReadWriteFile()
        .writeStringToFile(FileNames.ASSIGNATURES, jsonEncode(assignatures));*/
        dme.assigURL = new HashMap();
        dme.assigGuia = new HashMap();
        for (Assignatura a in assignatures.results) {
          AssignaturaURL assigURL = await rr.getAssignaturaURL(a);
          await ReadWriteFile()
              .writeStringToFile(FileNames.ASSIGNATURA_URL + a.id, jsonEncode(assigURL));
          dme.assigURL[a.id] = assigURL;
          AssignaturaGuia assigGuia = await rr.getAssignaturaGuia(a);
          await ReadWriteFile()
              .writeStringToFile(FileNames.ASSIGNATURA_GUIA + a.id, jsonEncode(assigGuia));
          dme.assigGuia[a.id] = assigGuia;
        }
        Requisits requisits = await rr.getRequisists();
        dme.requisits = requisits;
        await ReadWriteFile()
            .writeStringToFile(FileNames.REQUISITS, jsonEncode(requisits));

      }catch (e){
        /*   Assignatures assignatures = Assignatures.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.ASSIGNATURES)));*/
        List<SubjectHelper> subjectHelperList = await dbRepository.getAllSubjectHelper();
        List<Assignatura> assignaturaList = List();
        subjectHelperList.forEach((s) {
          assignaturaList.add(Assignatura.fromSubjectHelper(s));
        });
        dme.assignatures = Assignatures(assignaturaList.length,assignaturaList);
        _loadSubjectColor(dme.assignatures);
        dme.assigGuia = new HashMap();
        dme.assigURL = new HashMap();
        for (Assignatura a in dme.assignatures.results) {
          AssignaturaURL assigURL = AssignaturaURL.fromJson(jsonDecode(
              await ReadWriteFile().readStringFromFile(FileNames.ASSIGNATURA_URL + a.id)));
          dme.assigURL[a.id] = assigURL;
          String assigGuiaString =
          await ReadWriteFile().readStringFromFile(FileNames.ASSIGNATURA_GUIA + a.id);
          if (assigGuiaString != 'null') {
            AssignaturaGuia assigGuia =
            AssignaturaGuia.fromJson(jsonDecode(assigGuiaString));
            dme.assigGuia[a.id] = assigGuia;
          }
        }
        Requisits requisits = Requisits.fromJson(jsonDecode(
            await ReadWriteFile().readStringFromFile(FileNames.REQUISITS)));
        dme.requisits = requisits;
      }
    } else {
      /*   Assignatures assignatures = Assignatures.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.ASSIGNATURES)));*/
      List<SubjectHelper> subjectHelperList = await dbRepository.getAllSubjectHelper();
      List<Assignatura> assignaturaList = List();
      subjectHelperList.forEach((s) {
        assignaturaList.add(Assignatura.fromSubjectHelper(s));
      });
      dme.assignatures = Assignatures(assignaturaList.length,assignaturaList);
      _loadSubjectColor(dme.assignatures);
      dme.assigGuia = new HashMap();
      dme.assigURL = new HashMap();
      for (Assignatura a in dme.assignatures.results) {
        AssignaturaURL assigURL = AssignaturaURL.fromJson(jsonDecode(
            await ReadWriteFile().readStringFromFile(FileNames.ASSIGNATURA_URL + a.id)));
        dme.assigURL[a.id] = assigURL;
        String assigGuiaString =
        await ReadWriteFile().readStringFromFile(FileNames.ASSIGNATURA_GUIA + a.id);
        if (assigGuiaString != 'null') {
          AssignaturaGuia assigGuia =
          AssignaturaGuia.fromJson(jsonDecode(assigGuiaString));
          dme.assigGuia[a.id] = assigGuia;
        }
      }
      Requisits requisits = Requisits.fromJson(jsonDecode(
          await ReadWriteFile().readStringFromFile(FileNames.REQUISITS)));
      dme.requisits = requisits;
    }





    //Load lab ocupation
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('labs_loading')));

    if (await user.readFromPreferences('labs') == 'true') {
      try {
        dme.A5 =  await rr.getImageA5();
        dme.B5 =  await rr.getImageB5();
        dme.C6 =  await rr.getImageC6();
        dbRepository.cleanLabsTable();
        await dbRepository.insertLabImage(LabImageHelper('a5',dme.A5));
        await dbRepository.insertLabImage(LabImageHelper('b5',dme.B5));
        await dbRepository.insertLabImage(LabImageHelper('c6',dme.C6));
      }catch(e) {
        Dme().A5 = await dbRepository.getLabImagePathByName('a5');
        Dme().B5 = await dbRepository.getLabImagePathByName('b5');
        Dme().C6 = await dbRepository.getLabImagePathByName('c6');
      }

    } else {
      Dme().A5 = await dbRepository.getLabImagePathByName('a5');
      Dme().B5 = await dbRepository.getLabImagePathByName('b5');
      Dme().C6 = await dbRepository.getLabImagePathByName('c6');
    }



    //Load custom events
/*    Dme().customEvents = CustomEvents.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.CUSTOM_EVENTS)));*/
    List<CustomEventHelper> customEventHelperList = await dbRepository.getAllCustomEventHelper();
    List<CustomEvent> customEventList = List();
    customEventHelperList.forEach((ce) {
      customEventList.add(CustomEvent.fromCustomEventHelper(ce));
    });
    Dme().customEvents = CustomEvents(customEventList.length, customEventList);
/*    await dbRepository.cleanCustomEventHelperTable();
    //remove outdated custom events
    for (CustomEvent e in Dme().customEvents.results) {
      DateTime fie = DateTime.parse(e.fi);
      if (fie.isBefore(DateTime.now())) {
        Dme().customEvents.results.removeWhere((i) {
          return i.id == e.id;
        });
        Dme().customEvents.count -=1;
      }
    }
    Dme().customEvents.results.forEach((ce) async {
      await dbRepository.insertCustomEventHelper(CustomEventHelper.fromCustomEvent(ce, Dme().username));
    });*/
/*    await ReadWriteFile().writeStringToFile(
        FileNames.CUSTOM_EVENTS, jsonEncode(Dme().customEvents));*/

    //Load custom grades
    List<CustomGradeHelper> customGradeHelperList = await dbRepository.getAllCustomGradeHelper();
    List<CustomGrade> customGradeList = List();
    customGradeHelperList.forEach((cg) {
      customGradeList.add(CustomGrade.fromCustomGradeHelper(cg));
    });
    Dme().customGrades = CustomGrades(customGradeList.length, customGradeList);
/*    Dme().customGrades = CustomGrades.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.CUSTOM_GRADES)));*/

    //load custom downloads
    Dme().customDownloads = CustomDownloads.fromJson(jsonDecode(
        await ReadWriteFile().readStringFromFile(FileNames.CUSTOM_DOWNLOADS)));
  }

  Future<void> _downloadData(bool firstLogin) async {
    await dbRepository.openDB();
    if (!firstLogin) {
     dbRepository.cleanAllTable();
    }

    if (firstLogin) {
      await user.writeToPreferences('personal_info', 'false');
      Dme().bpersonal = false;
      await user.writeToPreferences('schedule', 'false');
      Dme().bschedule = false;
      await user.writeToPreferences('notices', 'true');
      Dme().bnotices = true;
      await user.writeToPreferences('events', 'true');
      Dme().bevents = true;
      await user.writeToPreferences('news', 'true');
      Dme().bnews = true;
      await user.writeToPreferences('subjects', 'false');
      Dme().bsubjects = false;
      await user.writeToPreferences('labs', 'true');
      Dme().blabs = true;
    }

    //load personal information
    loadingTextBloc.dispatch(
        LoadTextEvent(text: allTranslations.text('personal_info_loading')));
    String accessToken = await user.getAccessToken();
    String lang = await user.getPreferredLanguage();
    if (lang == '') {
      await user.setPreferredLanguage(allTranslations.currentLanguage);
      lang = allTranslations.currentLanguage;
    }
    RacoRepository rr = new RacoRepository(
        racoApiClient: RacoApiClient(
            httpClient: http.Client(), accessToken: accessToken, lang: lang));

    //Clear image cache to update avatar
    imageCache.clear();
    String imgPath = await rr.getImage();

    Me me = await rr.getMe();
    UserHelper meHelper = UserHelper.fromMe(me, imgPath);
    await dbRepository.cleanUserTable();
    await dbRepository.insertMeHelper(meHelper);


    //singleton data object
    Dme dme = Dme();
    dme.imgPath = imgPath;
    dme.username = me.username;
    dme.nom = me.nom;
    dme.cognoms = me.cognoms;
    dme.email = me.email;

   // await ReadWriteFile().writeStringToFile(FileNames.JO, jsonEncode(me));

    //Schedule information
    loadingTextBloc.dispatch(
        LoadTextEvent(text: allTranslations.text('schedule_loading')));
    Classes classes = await rr.getClasses();
    classes.results.forEach((cl) async {
      await dbRepository.insertScheduleHelper(ScheduleHelper.fromClasse(cl, me.username));
    });
    _fillSchedule(classes);
/*    await ReadWriteFile()
        .writeStringToFile(FileNames.CLASSES, jsonEncode(classes));*/

    //Notices information
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('notices_loading')));
    Avisos avisos = await rr.getAvisos();
    avisos.results.forEach((a) async {
      await dbRepository.insertNoticeHelper(NoticeHelper.fromAvis(a, me.username));
      a.adjunts.forEach((adj) async {
        await dbRepository.insertAttachmentHelper(AttachmentHelper.fromAdjunt(adj, a.id));
      });
    });
    dme.avisos = avisos;
   /* await ReadWriteFile()
        .writeStringToFile(FileNames.AVISOS, jsonEncode(avisos));*/

    //Events information
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('events_loading')));
    Events events = await rr.getEvents();
    events.results.forEach((e) async {
      await dbRepository.insertEventHelper(EventHelper.fromEvent(e));
    });
    dme.events = events;
/*    await ReadWriteFile()
        .writeStringToFile(FileNames.EVENTS, jsonEncode(events));*/

//Exams information

    //Semester to obtain exams information
    Quadrimestre actual = await rr.getQuadrimestreActual();
    //Get exams
    Examens examens = await rr.getExamens(actual);
    examens.results.forEach((e) async {
      await dbRepository.insertExamtHelper(ExamHelper.fromExamen(e, me.username));
    });
/*    await ReadWriteFile()
        .writeStringToFile(FileNames.EXAMENS, jsonEncode(examens));*/
    dme.examens = examens;


    //News information
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('news_loading')));
    Noticies noticies = await rr.getNoticies();
    noticies.results.forEach((n) async {
      await dbRepository.insertNewsHelper(NewsHelper.fromNoticia(n));
    });
    dme.noticies = noticies;
    /*await ReadWriteFile()
        .writeStringToFile(FileNames.NOTICIES, jsonEncode(noticies));*/

    //Subjects information
    loadingTextBloc.dispatch(
        LoadTextEvent(text: allTranslations.text('subjects_loading')));
    Assignatures assignatures = await rr.getAssignatures();
    assignatures.results.forEach((a) async {
      await dbRepository.insertSubjectHelper(SubjectHelper.fromAssignatura(a, me.username));
    });
    dme.assignatures = assignatures;
    _assignColor(assignatures, firstLogin);
/*    await ReadWriteFile()
        .writeStringToFile(FileNames.ASSIGNATURES, jsonEncode(assignatures));*/
    dme.assigURL = new HashMap();
    dme.assigGuia = new HashMap();
    for (Assignatura a in assignatures.results) {
      AssignaturaURL assigURL = await rr.getAssignaturaURL(a);
      await ReadWriteFile()
          .writeStringToFile(FileNames.ASSIGNATURA_URL + a.id, jsonEncode(assigURL));
      dme.assigURL[a.id] = assigURL;
      AssignaturaGuia assigGuia = await rr.getAssignaturaGuia(a);
      await ReadWriteFile()
          .writeStringToFile(FileNames.ASSIGNATURA_GUIA + a.id, jsonEncode(assigGuia));
      dme.assigGuia[a.id] = assigGuia;
    }
    Requisits requisits = await rr.getRequisists();
    dme.requisits = requisits;
    await ReadWriteFile()
        .writeStringToFile(FileNames.REQUISITS, jsonEncode(requisits));



    //Labs ocupation
    loadingTextBloc
        .dispatch(LoadTextEvent(text: allTranslations.text('labs_loading')));
    dme.A5 =  await rr.getImageA5();
    dme.B5 =  await rr.getImageB5();
    dme.C6 =  await rr.getImageC6();
    await dbRepository.insertLabImage(LabImageHelper('a5',dme.A5));
    await dbRepository.insertLabImage(LabImageHelper('b5',dme.B5));
    await dbRepository.insertLabImage(LabImageHelper('c6',dme.C6));
/*    user.writeToPreferences('a5', Dme().A5);
    user.writeToPreferences('b5', Dme().B5);
    user.writeToPreferences('c6', Dme().C6);*/


    //Custom events

    List<CustomEventHelper> customEventHelperList = await dbRepository.getAllCustomEventHelper();
    if (customEventHelperList.length > 0) {
      //Load custom events
/*      dme.customEvents = CustomEvents.fromJson(jsonDecode(
          await ReadWriteFile().readStringFromFile(FileNames.CUSTOM_EVENTS)));*/
      List<CustomEvent> customEventList = List();
      customEventHelperList.forEach((ce) {
        customEventList.add(CustomEvent.fromCustomEventHelper(ce));
      });
      dme.customEvents = CustomEvents(customEventList.length, customEventList);

    } else {
      List<CustomEvent> customEventList = new List<CustomEvent>();
      dme.customEvents = CustomEvents(0, customEventList);
/*      await ReadWriteFile().writeStringToFile(
          FileNames.CUSTOM_EVENTS, jsonEncode(dme.customEvents));*/
    }
    //Custom grades
    List<CustomGradeHelper> customGradeHelperList = await dbRepository.getAllCustomGradeHelper();
    if (customGradeHelperList.length > 0) {
      //Load custom grades
/*      dme.customGrades = CustomGrades.fromJson(jsonDecode(
          await ReadWriteFile().readStringFromFile(FileNames.CUSTOM_GRADES)));*/
      List<CustomGrade> customGradeList = List();
      customGradeHelperList.forEach((cg) {
        customGradeList.add(CustomGrade.fromCustomGradeHelper(cg));
      });
      dme.customGrades = CustomGrades(customGradeList.length, customGradeList);
    } else {
      List<CustomGrade> customGradesList = new List<CustomGrade>();
      dme.customGrades = CustomGrades(0, customGradesList);
/*      await ReadWriteFile().writeStringToFile(
          FileNames.CUSTOM_GRADES, jsonEncode(dme.customGrades));*/
    }

    //Custom downloads
    if (await ReadWriteFile().exists(FileNames.CUSTOM_DOWNLOADS)) {
      //Load custom grades
      dme.customDownloads = CustomDownloads.fromJson(jsonDecode(
          await ReadWriteFile().readStringFromFile(FileNames.CUSTOM_DOWNLOADS)));
    } else {
      List<String> customDownloadsList = new List<String>();
      dme.customDownloads = CustomDownloads(0, customDownloadsList);
      await ReadWriteFile().writeStringToFile(
          FileNames.CUSTOM_DOWNLOADS, jsonEncode(dme.customDownloads));
    }

  }

  void _fillSchedule(Classes classes) {
    Map<String, Classe> schedule = new HashMap();
    for (Classe cl in classes.results) {
      //0-4 represents monday-friday
      int col = cl.diaSetmana - 1;
      //0-12 represents 8:00-20:00
      int row = int.parse(cl.inici.split(":").first) - 8;
      for (int i = 0; i < cl.durada; i++) {
        String key = (row + i).toString() + '|' + col.toString();
        schedule[key] = cl;
      }
    }
    Dme dme = Dme();
    dme.schedule = schedule;
  }

  void _assignColor(Assignatures assignatures, bool firstLogin) async {
    List<int> generatedHues = List();
    Random rand = Random();
    Dme().assigColors = new HashMap();
     int minimumSeparation = (360/(assignatures.count*4)).round();
    for (Assignatura a in assignatures.results) {

      if (firstLogin) {
        int genHue = rand.nextInt(361);
        while(!_isValidColor(genHue, minimumSeparation,generatedHues)) {
          genHue = rand.nextInt(361);
        }
        generatedHues.add(genHue);

        HSVColor hsvcolor =
        HSVColor.fromAHSV(1, genHue.toDouble(), 0.5, 0.75);
        Color c = hsvcolor.toColor();
        Dme().assigColors[a.id] = c.value.toString();
        await user.writeToPreferences(a.id, c.value.toString());
        await user.writeToPreferences(a.id + 'default', c.value.toString());
      } else {
        Dme().assigColors[a.id] = await user.readFromPreferences(a.id);
      }
    }
    Dme().defaultAssigColors = new HashMap.from(Dme().assigColors);
  }

  bool _isValidColor(int v, int separation,List<int> generatedHues) {
    for (int i in generatedHues) {
      int diff = v - i;
      if (diff < 0) {
        diff = diff * -1;
      }
      if (diff < separation) {
        return false;
      }
    }
    return true;
  }

  void _loadSubjectColor(Assignatures assignatures) async {
    Dme().assigColors = new HashMap();
    Dme().defaultAssigColors = new HashMap();
    for (Assignatura a in assignatures.results) {
      String colorValue = await user.readFromPreferences(a.id);
      Dme().assigColors[a.id] = colorValue;
      String defaultv = await user.readFromPreferences(a.id + 'default');
      Dme().defaultAssigColors[a.id] = defaultv;
    }
  }
}
