import 'package:flutter/material.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web3dart/crypto.dart';
import 'package:objective_app2/utils/data.dart';



class SigningPage extends StatefulWidget {
  const SigningPage({Key? key}) : super(key: key);

  @override
  State<SigningPage> createState() => _SigningPageState();
}

class _SigningPageState extends State<SigningPage> {
  var connector, _session, _uri, _data;

  @override
  Widget build(BuildContext context) {
    var args = ModalRoute.of(context)!.settings.arguments as List;
    connector = args[0];
    _uri = args[1];
    _data = args[2];

    _session = connector.session;
    print(_session.accounts[0]);
    print(_uri);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Signing Page'),
      ),
      body: Center(
        child: Column(
          children: [
            const Text('Chain Hash:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${_data.metamaskHash}'),
            SizedBox(height: 20),
            const Text('Video Hash:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${_data.videoHash}'),
            SizedBox(height: 20),
            const Text('Signer Address:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${_session.accounts[0]}'),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () =>
                signMessageWithMetamask(
                  context,
                  generateSessionMessage(_session.accounts[0])),
              child: const Text('Sign Message'),
            ),
          ],
        )
      ),
    );
  }

  signMessageWithMetamask(BuildContext context, String message) async {
    if (connector.connected) {
      try {
        print("Message received");
        print(message);

        EthereumWalletConnectProvider provider =
            EthereumWalletConnectProvider(connector);
        launchUrlString(_uri, mode: LaunchMode.externalApplication);
        print('te');
        var signature = await provider.personalSign(
            message: message, address: _session.accounts[0], password: '');
        print(signature);
        setState(() {
          _data.metamaskHash = signature;
        });
      } catch (exp) {
        print("Error while signing transaction");
        print(exp);
        print(exp.toString());
      }
    }
  }

  String generateSessionMessage(String accountAddress) {
    return 'video hash: ${_data.videoHash}';
  }
}
