import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/cupertino.dart' as prefix0;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/block_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_colorpicker/material_picker.dart';
import 'package:raco/src/blocs/translations/translations.dart';
import 'package:raco/src/resources/global_translations.dart';
import 'package:raco/src/resources/user_repository.dart';
import 'package:raco/src/utils/app_colors.dart';

class Configuration extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return ConfigurationState();
  }
}

class ConfigurationState extends State<Configuration>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _translationBloc = BlocProvider.of<TranslationsBloc>(context);

    _onLanguageButtonPressed() async{
      await showDialog(context: context, builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return new SimpleDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20.0))),
              children: <Widget>[
                new SimpleDialogOption(
                  child: new Text(allTranslations.text('ca')),
                  onPressed: (){
                    _translationBloc
                        .dispatch(TranslationsChangedEvent(newLangCode: 'ca'));
                    Navigator.of(context).pop();
                  },
                ),
                Divider(),
                new SimpleDialogOption(
                  child: new Text(allTranslations.text('es')),
                  onPressed: (){
                    _translationBloc
                        .dispatch(TranslationsChangedEvent(newLangCode: 'es'));
                    Navigator.of(context).pop();
                  },
                ),
                Divider(),
                new SimpleDialogOption(
                  child: new Text(allTranslations.text('en')),
                  onPressed: (){
                    _translationBloc
                        .dispatch(TranslationsChangedEvent(newLangCode: 'en'));
                    Navigator.of(context).pop();
                  },
                )
              ],
            );
          },
        );
      });
    }



    _onSelectColor(String mode) {
      Color s = AppColors().primary;
      if (mode == 's') {
        s = AppColors().accentColor;
      } else if (mode == 'p') {
        s = AppColors().primary;
      }
      showDialog(

        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20.0))),
            title: Text(allTranslations.text('select_color'),overflow: TextOverflow.visible,),
            content: SingleChildScrollView(
              child: MaterialPicker(
                 pickerColor: s,
                 onColorChanged: (Color c) {
                    print(c.toString());
                    s = c;
                 },
               ),
            ),
            actions: <Widget>[
              FlatButton(
                child:  Text(allTranslations.text('default'),overflow: TextOverflow.visible,),
                onPressed: () {
                  if (mode == 'p') {
                    AppColors().primary = AppColors().default_primary;
                    user.writeToPreferences('primary_color', AppColors().default_primary.value.toString());
                  } else if (mode == 's') {
                    AppColors().accentColor = AppColors().default_accentColor;
                    user.writeToPreferences('secondary_color', AppColors().default_accentColor.value.toString());
                  }
                  String cur = allTranslations.currentLanguage;
                  String an;
                  if (cur == 'es') {
                    an = 'en';
                  } else if (cur == 'ca') {
                    an = 'en';
                  } else {
                    an = 'ca';
                  }
                  _translationBloc
                      .dispatch(TranslationsChangedEvent(newLangCode: an));
                  _translationBloc
                      .dispatch(TranslationsChangedEvent(newLangCode: cur));
                  Navigator.of(context).pop();
                },
              ),
              FlatButton(
                child:  Text(allTranslations.text('cancel'),overflow: TextOverflow.visible,),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              FlatButton(
                child:  Text(allTranslations.text('accept'),overflow: TextOverflow.visible,),
                onPressed: () {
                  if (mode == 'p') {
                    AppColors().primary = s;
                    user.writeToPreferences('primary_color', s.value.toString());
                  } else if (mode == 's') {
                    AppColors().accentColor = s;
                    user.writeToPreferences('secondary_color', s.value.toString());
                  }
                  String cur = allTranslations.currentLanguage;
                  String an;
                  if (cur == 'es') {
                    an = 'en';
                  } else if (cur == 'ca') {
                    an = 'en';
                  } else {
                    an = 'ca';
                  }
                  _translationBloc
                      .dispatch(TranslationsChangedEvent(newLangCode: an));
                  _translationBloc
                      .dispatch(TranslationsChangedEvent(newLangCode: cur));
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }
      );
    }

    return new Scaffold(
        appBar: AppBar(
          title: Text(allTranslations.text('configuration')),
        ),
        body: Container(
          child: ListView(
            children: <Widget>[
              _language(() => _onLanguageButtonPressed()),
              Divider(),
              _selectColor(allTranslations.text('primary_color'),() => _onSelectColor('p')),
              Divider(),
              _selectColor(allTranslations.text('secondary_color'), () => _onSelectColor('s'))
            ],
          ),
        ));
  }

  Widget _selectColor(String t, VoidCallback onColorTap) {
    return ListTile(
      onTap: () => onColorTap(),
      trailing: t == allTranslations.text('primary_color') ? CircleAvatar(backgroundColor: AppColors().primary,) : CircleAvatar(backgroundColor: AppColors().accentColor,),
      title: Text(
        t,
        overflow: TextOverflow.visible,
      ),
    );
  }

  Widget _language(VoidCallback onLanguageTap) {
    return ListTile(
      onTap: () => onLanguageTap(),
      leading: Icon(Icons.language),
      title: Text(
        allTranslations.text('language'),
        overflow: TextOverflow.visible,
      ),
    );
  }


}
