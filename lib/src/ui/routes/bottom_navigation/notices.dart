import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:meta/meta.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:raco/src/data/dme.dart';
import 'package:raco/src/models/classes.dart';
import 'package:raco/src/models/models.dart';
import 'package:raco/src/repositories/repositories.dart';
import 'package:raco/src/resources/global_translations.dart';
import 'package:intl/intl.dart';
import 'package:raco/src/resources/user_repository.dart';
import 'package:raco/src/utils/file_names.dart';
import 'package:raco/src/utils/read_write_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'notice.dart';

class Notices extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return NoticiesState();
  }
}

class NoticiesState extends State<Notices> with SingleTickerProviderStateMixin {
  Assignatures assignatures = Dme().assignatures;
  TabController _tabController;
  RefreshController _refreshController =
      RefreshController(initialRefresh: false);

  @override
  void initState() {
    int size = assignatures.count + 1;
    _tabController = new TabController(length: size, vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: TabBar(
        controller: _tabController,
        tabs: _tabs(),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabViews(),
      ),
    );
  }

  List<Widget> _tabs() {
    List<Tab> tabs = [
      Tab(
        text: allTranslations.text('all'),
      )
    ];
    tabs.addAll(assignatures.results.map((Assignatura a) {
      print('HHHH:' + a.nom + ':hhh');
      return Tab(
        text: a.id,
      );
    }).toList());
    return tabs;
  }

  //---------------------------

  void _onRefresh() async {
    //update notices
    String accessToken = await user.getAccessToken();
    String lang = await user.getPreferredLanguage();
    RacoRepository rr = new RacoRepository(
        racoApiClient: RacoApiClient(
            httpClient: http.Client(), accessToken: accessToken, lang: lang));
    Avisos avisos = await rr.getAvisos();
    Dme().avisos = avisos;
    await ReadWriteFile()
        .writeStringToFile(FileNames.AVISOS, jsonEncode(avisos));
    setState(() {

    });
    _refreshController.refreshCompleted();
  }

  //_------------------------------------
  List<Widget> _tabViews() {
    List<Container> tabViews = [
      Container(
        child: Container(
          child: SmartRefresher(
              enablePullDown: true,
              enablePullUp: false,
              header: BezierCircleHeader(),
              controller: _refreshController,
              onRefresh: _onRefresh,
              child: _noticesList(Dme().avisos.results)),
        ),
      )
    ];
    tabViews.addAll(assignatures.results.map((Assignatura a) {
      List<Avis> avisos = Dme()
          .avisos
          .results
          .where((avis) => avis.codiAssig == a.sigles)
          .toList();
      return Container(
        child: SmartRefresher(
            enablePullDown: true,
            enablePullUp: false,
            header: BezierCircleHeader(),
            controller: _refreshController,
            onRefresh: _onRefresh,
            child: _noticesList(avisos)),
      );
    }).toList());
    return tabViews;
  }

  Widget _noticesList(List<Avis> avisos) {
    if (avisos.length == 0) {
      return ListView(
        children: <Widget>[
          Container(
            padding: EdgeInsets.only(top: ScreenUtil().setHeight(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  allTranslations.text('no_notices'),
                  style: TextStyle(color: Colors.grey),
                )
              ],
            ),
          )
        ],
      );
    } else {
      return ListView(
        children: _avisos(avisos),
      );
    }
  }

  List<Widget> _avisos(List<Avis> avisos) {
    avisos.sort((a, b) {
      DateFormat format = DateFormat('yyyy-M-dTH:m:s');
      DateTime ta = format.parse(a.dataModificacio);
      DateTime tb = format.parse(b.dataModificacio);
      return tb.compareTo(ta);
    });

    DateFormat format = DateFormat('yyyy-M-dTH:m:s');
    var formatter = new DateFormat.yMMMMd(allTranslations.currentLanguage);

    return avisos.map((Avis avis) {
      Color color;
      if (Dme().assigColors[avis.codiAssig] == null) {
        color = Colors.blueGrey;
      } else {
        int codi = int.parse(Dme().assigColors[avis.codiAssig]);
        color = Color(codi);
      }

      DateTime ta = format.parse(avis.dataModificacio);
      String time = formatter.format(ta);
      if (avis.adjunts.length > 0) {
        return Card(
          child: InkWell(
            onTap: () => _onTap(avis),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color,
                child: FittedBox(
                  child: Text(avis.codiAssig),
                ),
              ),
              title: Text(avis.titol),
              trailing: Container(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(avis.adjunts.length.toString()),
                    Icon(Icons.attach_file)
                  ],
                ),
              ),
              subtitle: Text(time),
            ),
          ),
        );
      }
      return Card(
        child: InkWell(
          onTap: () => _onTap(avis),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color,
              child: FittedBox(
                child: Text(avis.codiAssig),
              ),
            ),
            title: Text(avis.titol),
            subtitle: Text(time),
          ),
        ),
      );
    }).toList();
  }

  _onTap(Avis avis) {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => Notice(avis: avis)));
  }
}
