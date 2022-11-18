import 'package:flutter/material.dart';

showActionDialog(BuildContext context, title, message, String action) async {
  // set up the button
  Widget closeButton = TextButton(
    child: const Text("Close"),
    onPressed: () {
      print('Cancelling after $message');
      Navigator.pop(context, false);
    },
  );

  Widget retryButton = TextButton(
    child: Text(action),
    onPressed: () {
      print('$action after $message');
      Navigator.pop(context, true);
    },
  );

  // set up the AlertDialog
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      retryButton,
      closeButton,
    ],
  );

  // show the dialog
  return await showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}

showRetryDialog(BuildContext context, title, message) async {
  return showActionDialog(context, title, message, 'Retry');
}

showOKDialog(BuildContext context, title, message) async {
    Widget closeButton = TextButton(
      child: const Text("Ok"),
      onPressed: () {
        print('Ok after $message');
        Navigator.pop(context, false);
      },
    );

  // set up the AlertDialog
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      closeButton,
    ],
  );

  // show the dialog
  return await showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}
