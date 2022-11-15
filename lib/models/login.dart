import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:walletconnect_secure_storage/walletconnect_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/services.dart';
import 'dart:async';

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

    printWC('login func ${loggedIn}, ${connector!.connected}');

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

  printWC(message) {
    print('WC: $message');
  }

  Future<void> initConnector() async {
    if(connector != null) {
      return;
    }

    printWC('initConnector');
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

    connector!.registerListeners(
      onConnect: (SessionStatus status) {
        printWC('onConnect ${status}');
        connectedAccount = Account.fromSession(connector!.session);
        onLogin(connectedAccount!);
      },
      onSessionUpdate: (WCSessionUpdateResponse response) {
        printWC('onSessionUpdate ${response}');
        connectedAccount = Account.fromSession(connector!.session);
        onUpdate(connectedAccount!);
      },
      onDisconnect: () {
        printWC('onDisconnect');
        connectedAccount = null;
        onLogout();
      },
    );

    if(connector!.connected && session != null) {
      printWC('restoring account from session, connector connected');
      connectedAccount = Account.fromSession(session);
      onLogin(connectedAccount!);
    }
  }

  Future<String> signMessageWithMetamask(String message) async {
    if (connector!.connected) {
      // printWC('reconnecting just in fucking case...');
      // connector!.reconnect();
      printWC("Message received");
      printWC(message);

      EthereumWalletConnectProvider provider =
          EthereumWalletConnectProvider(connector!);

      launchUrlString(uri!, mode: LaunchMode.externalApplication);

      printWC('signing message');
      Future<dynamic> future =  provider.personalSign(
        message: message,
        address: connector!.session.accounts[0],
        password: '',
      );

      Completer<dynamic> completer = Completer();
      future.then(completer.complete).catchError(completer.completeError);

      while(true) {
        await Future.delayed(const Duration(seconds: 1));
        printWC('sign completer.isCompleted: ${completer.isCompleted}');
        if(completer.isCompleted) {
          break;
        }
      }

      return await future;
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
      // printWC('reconnecting just in fucking case...');

      try {
        printWC("Sending transaction");
        printWC(request.getIntegerDirection());
        printWC(request.getIntegerLatitude());
        printWC(request.getIntegerLongitude());
        printWC(request.startTimestamp);
        printWC(request.getIntegerEndTimestamp());

        var contractAddress = '0xC6ea1442139Fd2938098E638213302b05DDD6CC6';

        DeployedContract contract = await getContract();
        ContractFunction function = contract.function("submitRequest");

        printWC('constracting data');
        var data_bytes = function.encodeCall([
            BigInt.from(request.getIntegerLatitude()),
            BigInt.from(request.getIntegerLongitude()),
            BigInt.from(request.startTimestamp),
            BigInt.from(request.getIntegerEndTimestamp()),
            BigInt.from(request.getIntegerDirection()),
        ]);
        printWC(data_bytes);

        EthereumWalletConnectProvider provider = EthereumWalletConnectProvider(connector!, chainId: 5);
        launchUrlString(uri!, mode: LaunchMode.externalApplication);

        Future<dynamic> future = provider.sendTransaction(
          from: connector!.session.accounts[0],
          to: contractAddress,
          value: EtherAmount.fromUnitAndValue(EtherUnit.finney, BigInt.from(50)).getInWei,
          gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, BigInt.from(100)).getInWei, // get gas price estimation from somewhere.
          gas: 150000, // default: 90000
          data: data_bytes,
        );

        Completer<dynamic> completer = Completer();
        future.then(completer.complete).catchError(completer.completeError);

        while(true) {
          await Future.delayed(const Duration(seconds: 1));
          printWC('sendTx completer.isCompleted: ${completer.isCompleted}');
          if(completer.isCompleted) {
            break;
          }
        }

        var tx = await future;

        printWC(tx);
        request.txHash = tx;
        return true;
      } catch (exp) {
        printWC("Error while sending transaction");
        printWC(exp);
        printWC(exp.toString());
      }
    }
    return false;
  }
}