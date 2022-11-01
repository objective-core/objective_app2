import 'package:flutter/material.dart';
import 'package:objective_app2/utils/routes.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:slider_button/slider_button.dart';
import 'package:walletconnect_secure_storage/walletconnect_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:objective_app2/utils/data.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  var connector, sessionStorage;
  var _session, _uri;

  var videoData = Data(videoPath: '', videoHash: '', metamaskHash: '');

  final storage = new FlutterSecureStorage();

  loginUsingMetamask(BuildContext context) async {
    if (!connector.connected) {
      try {
        var session = await connector.createSession(onDisplayUri: (uri) async {
          _uri = uri;
          await storage.write(key: 'wc-uri', value: uri);
          await launchUrlString(uri, mode: LaunchMode.externalApplication);
        });
              print(session.accounts[0]);
              print(session.chainId);
        setState(() {
          _session = session;
        });
      } catch (exp) {
        print(exp);
      }
    } else {
      _session = connector.session;
      _uri = await storage.read(key: 'wc-uri');
      print("already connected");
    }
  }

  @override
  Widget build(BuildContext context) {
    print('buiding');
    // spawn a new connector;
    if (connector == null) {
      connectToWallet();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Page'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/objective_logo.png',
                fit: BoxFit.fitHeight,
                height: 200,
              ),
              (_session != null) ? Container(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account',
                        style: GoogleFonts.merriweather(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${_session.accounts[0]}',
                        style: GoogleFonts.inconsolata(fontSize: 16),
                      ),
                      SizedBox(
                        height: 20,
                      ),
                      Row(
                        children: [
                          Text(
                            'Chain: ',
                            style: GoogleFonts.merriweather(
                              fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              getNetworkName(_session.chainId),
                              style: GoogleFonts.inconsolata(fontSize: 16),
                            )
                        ],
                      ),
                      (_session.chainId != 5)
                      ? Row(
                          children: const [
                            Icon(Icons.warning,
                              color: Colors.redAccent, size: 15),
                            Text('Network not supported. Switch to '),
                            Text(
                              'Goerli Testnet',
                              style:
                                TextStyle(fontWeight: FontWeight.bold),
                            )
                          ],
                        )
                      : Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                              child: Row(
                                children: const [
                                  Icon(Icons.check_circle,
                                    color: Colors.green, size: 15),
                                  Text('Network supported. You are good to go!')
                                ],
                              ),
                            ),
                            SizedBox(height: 10),
                            Text('video hash: ${videoData.videoHash}'),
                            SizedBox(height: 10),
                            Text('metamask hash: ${videoData.metamaskHash}'),
                            SizedBox(height: 10),
                            Container(
                              alignment: Alignment.center,
                              child: SliderButton(
                                action: () async {
                                  Navigator.pushNamed(context, AppRoutes.signingRoute, arguments: [connector, _uri, videoData]);
                                },
                                label: const Text('Slide to sign some message:)'),
                                icon: const Icon(Icons.check),
                              ),
                            ),
                            SizedBox(height: 10),
                            Container(
                              alignment: Alignment.center,
                              child: SliderButton(
                                action: () async {
                                  Navigator.pushNamed(context, AppRoutes.videoRequestRoute, arguments: [connector, _uri]);
                                },
                                label: const Text('Slide to send video request'),
                                icon: const Icon(Icons.check),
                              ),
                            ),
                            SizedBox(height: 10),
                            Container(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: () async {
                                  Navigator.pushNamed(context, AppRoutes.recorderRoute, arguments: videoData);
                                },
                                child: const Text('Record video'),
                              ),
                            ),
                            Container(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: () async {
                                  setState(() {});
                                },
                                child: const Text('Refresh'),
                              ),
                            ),
                          ],
                        ),
                    ]
                  )
                )
              : ElevatedButton(
                onPressed: () => {loginUsingMetamask(context)},
                child: const Text("Connect with Metamask")
              ),
            ],
          )
        )
      )
    );
  }

  Future<bool> connectToWallet() async {
    print('connect to wallet');
    sessionStorage = WalletConnectSecureStorage();

    var __session = await sessionStorage.getSession();
    var __uri = await storage.read(key: 'wc-uri');

    setState(() {
      _session = __session;
      _uri = __uri;
    });

    print(_session);
    print(_uri);
    print(_session.accounts[0]);
    print(_session.chainId);

    connector =  WalletConnect(
      bridge: 'https://bridge.walletconnect.org',
      session: _session,
      sessionStorage: sessionStorage,
      clientMeta: const PeerMeta(
        name: 'Objective',
        description: 'Camera for Objective reporters.',
        url: 'https://walletconnect.org',
        icons: [
          'https://files.gitbook.com/v0/b/gitbook-legacy-files/o/spaces%2F-LJJeCjcLrr53DcT1Ml7%2Favatar.png?alt=media'
        ])
    );

    connector.on(
        'connect',
        (session) => setState(
              () {
                _session = session;
              },
            ));
    connector.on(
        'session_update',
        (payload) => setState(() {
              _session = payload;
              print(payload);
            }));
    connector.on(
        'disconnect',
        (payload) => setState(() {
              _session = null;
            }));

    return true;
  }

  getNetworkName(chainId) {
    switch (chainId) {
      case 1:
        return 'Ethereum Mainnet';
      case 3:
        return 'Ropsten Testnet';
      case 4:
        return 'Rinkeby Testnet';
      case 5:
        return 'Goerli Testnet';
      case 42:
        return 'Kovan Testnet';
      case 137:
        return 'Polygon Mainnet';
      case 80001:
        return 'Mumbai Testnet';
      default:
        return 'Unknown Chain';
    }
  }
}
