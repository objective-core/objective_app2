import 'package:flutter/material.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web3dart/crypto.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:http/http.dart' as http;



class SigningPage extends StatefulWidget {
  const SigningPage({Key? key}) : super(key: key);

  @override
  State<SigningPage> createState() => _SigningPageState();
}

class _SigningPageState extends State<SigningPage> {
  late Data data;

  @override
  Widget build(BuildContext context) {
    data = ModalRoute.of(context)!.settings.arguments as Data;

    print(data.connector!.session);
    print(data.connectionUri);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Signing Page'),
      ),
      body: Center(
        child: Column(
          children: [
            const Text('Chain Hash:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${data.video!.signature}'),
            SizedBox(height: 20),
            const Text('Video Hash:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${data.video!.hash}'),
            SizedBox(height: 20),
            const Text('Signer Address:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(data.connector!.session.accounts[0]),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () =>
                signMessageWithMetamask(
                  context,
                  generateSessionMessage(data.connector!.session.accounts[0])),
              child: const Text('Sign Message'),
            ),
          ],
        )
      ),
    );
  }

  signMessageWithMetamask(BuildContext context, String message) async {
    if (data.connector!.connected) {
      try {
        print("Message received");
        print(message);

        EthereumWalletConnectProvider provider =
            EthereumWalletConnectProvider(data.connector!);
        launchUrlString(data.connectionUri!, mode: LaunchMode.externalApplication);

        var signature = await provider.personalSign(
            message: message, address: data.connector!.session.accounts[0], password: '');
        print(signature);
        setState(() {
          data.video!.signature = signature;
        });

        uploadVideo();
      } catch (exp) {
        print("Error while signing transaction");
        print(exp);
        print(exp.toString());
      }
    }
  }

  uploadVideo() async {
    // curl -v \
    // -F lat=12 \
    // -F long=12 \
    // -F start=123123 \
    // -F end=123140 \
    // -F median_direction=12 \
    // -F signature=test \
    // -F request_id=test-request-id-1 \
    // -F expected_hash=QmNT8axScpvoXJeKaoeZcD7E9ew9eSNp4EePXjwB62mrv4 \
    // -F file=@requirements.in \
    // https://api.objective.camera/upload/

    var url = Uri.https('api.objective.camera', 'upload/');
    print(url);
    var request = http.MultipartRequest("POST", url);

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        data.video!.path!,
      )
    );
    request.fields.addAll({
      'lat': data.currentPosition!.latitude.toString(),
      'long': data.currentPosition!.longitude.toString(),
      'start': data.video!.startTime.millisecondsSinceEpoch.toString(),
      'end': data.video!.endTime!.millisecondsSinceEpoch.toString(),
      'median_direction': data.currentPosition!.heading.truncate().toString(),
      'signature': data.video!.signature!,
      'request_id': 'реквест айди',
      'expected_hash': data.video!.hash!,
    });

    request.send().then((response) async {
      print(response.statusCode);
      print(await response.stream.bytesToString());
    });
  }

  String generateSessionMessage(String accountAddress) {
    return 'video hash: ${data.video!.hash}';
  }
}
