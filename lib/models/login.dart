import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:walletconnect_secure_storage/walletconnect_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/services.dart';

typedef OnLogin = void Function(Account account);
typedef OnLogout = void Function();
typedef OnUpdate = void Function(Account acccount);


class Account {
  final String address;
  final int networkId;

  Account(
    this.address,
    this.networkId,
  );

  static Account fromSession(WalletConnectSession session) {
    return Account(session.accounts.first, session.chainId);
  }

  String get networkName => getNetworkName(networkId);

  static String getNetworkName(chainId) {
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


class LoginModel {
  Future<bool> get signedIn async {
    return false;
  }

  WalletConnect? connector;
  String? uri;
  Account? connectedAccount;
  WalletConnectSecureStorage sessionStorage = WalletConnectSecureStorage();
  List<int> supportedNetworks;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  final OnLogin onLogin;
  final OnLogout onLogout;
  final OnUpdate onUpdate;

  LoginModel({
    required this.supportedNetworks,
    required this.onLogin,
    required this.onLogout,
    required this.onUpdate,
  });

  bool get loggedIn => connectedAccount != null;
  bool get networkSupported => supportedNetworks.contains(connectedAccount!.networkId);
  Account get account => connectedAccount!;

  login() async {
    await initConnector();

    print('login func ${loggedIn}, ${connector!.connected}');

    if (!connector!.connected) {
      await connector!.createSession(onDisplayUri: (connectionUri) async {
        uri = connectionUri;
        await storage.write(key: 'wc-uri', value: uri);
        await launchUrlString(uri!, mode: LaunchMode.externalApplication);
      });
    }

    if(connector!.connected) {
      connectedAccount = Account.fromSession(connector!.session);
      onLogin(connectedAccount!);
    }
  }

  Future<void> initConnector() async {
    if(connector != null) {
      return;
    }

    print('initConnector');
    sessionStorage = WalletConnectSecureStorage();

    var session = await sessionStorage.getSession();
    uri = await storage.read(key: 'wc-uri');

    connector = WalletConnect(
      bridge: 'https://bridge.walletconnect.org',
      session: session,
      sessionStorage: sessionStorage,
      clientMeta: const PeerMeta(
        name: 'Objective',
        description: 'Camera for Objective reporters.',
        url: 'https://objective.camera',
        icons: [
          'https://files.gitbook.com/v0/b/gitbook-legacy-files/o/spaces%2F-LJJeCjcLrr53DcT1Ml7%2Favatar.png?alt=media'
        ])
    );

    // Supported events: connect, disconnect, session_request, session_update
    connector!.on('connect', (_) {
      print('connected');
      connectedAccount = Account(connector!.session.accounts.first, connector!.session.chainId);
      onLogin(connectedAccount!);
    });

    connector!.on('session_update', (_) {
      print('session_update');
      connectedAccount = Account(connector!.session.accounts.first, connector!.session.chainId);
      onUpdate(connectedAccount!);
    });

    connector!.on('session_request', (_) {
      print('session_request');
      connectedAccount = Account(connector!.session.accounts.first, connector!.session.chainId);
      onUpdate(connectedAccount!);
    });

    connector!.on('disconnect', (_) {
      print('disconnect');
      connectedAccount = null;
      onLogout();
    });

    if(connector!.connected) {
      connectedAccount = Account.fromSession(connector!.session);
      onLogin(connectedAccount!);
    }
  }

  Future<String> signMessageWithMetamask(String message) async {
    if (connector!.connected) {
      print("Message received");
      print(message);

      EthereumWalletConnectProvider provider =
          EthereumWalletConnectProvider(connector!);

      launchUrlString(uri!, mode: LaunchMode.externalApplication);

      return await provider.personalSign(
        message: message,
        address: connector!.session.accounts[0],
        password: '',
      );
    }

    // TODO: raise exception?
    return '';
  }

  Future<DeployedContract> getContract() async {
    String abi = await rootBundle.loadString("assets/contracts/VideoRequester.json");

    String contractAddress = "0xe011eA99393AaB86E59fd57Ff4DbB48825E36290";
    String contractName = "VideoRequester";

    DeployedContract contract = DeployedContract(
      ContractAbi.fromJson(abi, contractName),
      EthereumAddress.fromHex(contractAddress),
    );

    return contract;
  }

  Future<bool> sendTxViaMetamask(VideoRequestData request) async {
    if (connector!.connected) {
      try {
        print("Sending transaction");
        print(request.getIntegerDirection());
        print(request.getIntegerLatitude());
        print(request.getIntegerLongitude());
        print(request.startTimestamp);
        print(request.getIntegerEndTimestamp());

        var function_address = 'd8484ca7';
        var requestId = 1;
        var contractAddress = '0xa8cbf99c7ea18a8e6a2ea34619609a0aa9e77211';

        DeployedContract contract = await getContract();
        ContractFunction function = contract.function("submitRequest");

        print('constracting data');
        var data_bytes = function.encodeCall([
            "1",
            BigInt.from(request.getIntegerLatitude()),
            BigInt.from(request.getIntegerLongitude()),
            BigInt.from(request.startTimestamp),
            BigInt.from(request.getIntegerEndTimestamp()),
            BigInt.from(request.getIntegerDirection()),
        ]);
        print(data_bytes);

        EthereumWalletConnectProvider provider = EthereumWalletConnectProvider(connector!, chainId: 5);
        launchUrlString(uri!, mode: LaunchMode.externalApplication);

        var tx = await provider.sendTransaction(
          from: connector!.session.accounts[0],
          to: contractAddress,
          value: EtherAmount.fromUnitAndValue(EtherUnit.finney, BigInt.from(1)).getInWei,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, BigInt.from(100)).getInWei, // get gas price estimation from somewhere.
          gas: 150000, // default: 90000
          data: data_bytes,
        );

        print(tx);
        request.txHash = tx;
        return true;
      } catch (exp) {
        print("Error while sending transaction");
        print(exp);
        print(exp.toString());
      }
    }
    return false;
  }
}