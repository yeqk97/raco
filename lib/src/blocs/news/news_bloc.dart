import 'dart:async';
import 'dart:convert';
import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:oauth2/oauth2.dart';
import 'package:raco/src/blocs/authentication/authentication.dart';
import 'package:raco/src/data/dme.dart';
import 'package:raco/src/models/db_helpers/news_helper.dart';
import 'package:raco/src/models/models.dart';
import 'package:raco/src/repositories/db_repository.dart';
import 'package:raco/src/repositories/raco_api_client.dart';
import 'package:raco/src/repositories/raco_repository.dart';
import 'package:raco/src/resources/authentication_data.dart';
import 'package:raco/src/repositories/user_repository.dart';
import 'package:raco/src/utils/file_names.dart';
import 'package:raco/src/utils/keys.dart';
import 'package:raco/src/utils/read_write_file.dart';
import 'package:http/http.dart' as http;

import 'news.dart';

class NewsBloc extends Bloc<NewsEvent, NewsState> {
  final AuthenticationBloc authenticationBloc;

  NewsBloc({
    @required this.authenticationBloc,
  }) : assert(authenticationBloc != null);
  NewsState get initialState => NewsInitState();

  @override
  Stream<NewsState> mapEventToState(NewsEvent event) async* {
    if (event is NewsInitEvent) {
      yield NewsInitState();
    }
    if (event is NewsChangedEvent) {
      try {
        Credentials c = await user.getCredentials();
        if(c.isExpired ) {
          c = await c.refresh(identifier: AuthenticationData.identifier,secret: AuthenticationData.secret,);
          await user.persistCredentials(c);
        }
        //update news
        bool canUpdate = true;
        if (await user.isPresentInPreferences(Keys.LAST_NEWS_REFRESH)) {
          if (DateTime.now()
              .difference(DateTime.parse(
              await user.readFromPreferences(Keys.LAST_NEWS_REFRESH)))
              .inMinutes <
              5) {
            canUpdate = false;
          }
        }
        if (canUpdate) {
          String accessToken = await user.getAccessToken();
          String lang = await user.getPreferredLanguage();
          RacoRepository rr = new RacoRepository(
              racoApiClient: RacoApiClient(
                  httpClient: http.Client(),
                  accessToken: accessToken,
                  lang: lang));
          Noticies noticies = await rr.getNoticies();
/*          await ReadWriteFile()
              .writeStringToFile(FileNames.NOTICIES, jsonEncode(noticies));*/
          noticies.results.forEach((n) async {
            await dbRepository.insertNewsHelper(NewsHelper.fromNoticia(n));
          });
          Dme().noticies = noticies;
          user.writeToPreferences(
              Keys.LAST_NEWS_REFRESH, DateTime.now().toIso8601String());
          yield UpdateNewsSuccessfullyState();
        } else {
          yield UpdateNewsTooFrequentlyState();
        }
      } catch(e) {
        yield UpdateNewsErrorState();
      }

    }
  }
}
