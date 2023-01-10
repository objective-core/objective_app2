import 'package:flutter/material.dart';
import 'package:objective_app2/utils/routes.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:walletconnect_secure_storage/walletconnect_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:geolocator/geolocator.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  var sessionStorage;
  var _session;

  var data = Data();
  final storage = new FlutterSecureStorage();

  loginUsingMetamask(BuildContext context) async {
    if (!data.connector!.connected) {
      try {
        var session = await data.connector!.createSession(onDisplayUri: (uri) async {
          data.connectionUri = uri;
          await storage.write(key: 'wc-uri', value: uri);
          await launchUrlString(uri, mode: LaunchMode.externalApplication);
        });

        if(session.chainId == 5) {
          Navigator.pushNamed(context, AppRoutes.requestPickerRoute, arguments: data);
        }

        setState(() {
          _session = session;
        });
      } catch (exp) {
        print(exp);
      }
    } else {
      _session = data.connector!.session;
      data.connectionUri = await storage.read(key: 'wc-uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    // spawn a new connector;
    if (data.connector == null) {
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
                            Container(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await Navigator.pushNamed(context, AppRoutes.recorderRoute, arguments: data);
                                  setState(() {});
                                },
                                child: const Text('Record video'),
                              ),
                            ),
                            Container(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await Navigator.pushNamed(context, AppRoutes.locationPickerRoute, arguments: data);
                                  setState(() {});
                                },
                                child: const Text('Pick location'),
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
    sessionStorage = WalletConnectSecureStorage();

    var __session = await sessionStorage.getSession();
    var uri = await storage.read(key: 'wc-uri');

    setState(() {
      _session = __session;
      data.connectionUri = uri;
    });

    data.connector =  WalletConnect(
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

    data.connector!.on(
        'connect',
        (session) => setState(
              () {
                _session = session;
              },
            ));
    data.connector!.on(
        'session_update',
        (payload) => setState(() {
              _session = payload;
            }));
    data.connector!.on(
        'disconnect',
        (payload) => setState(() {
              _session = null;
            }));

    if(data.connector!.session.chainId == 5) {
      Navigator.pushNamed(context, AppRoutes.requestPickerRoute, arguments: data);
    }

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
