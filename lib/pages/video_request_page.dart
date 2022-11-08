import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:objective_app2/utils/data.dart';

import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:web3dart/web3dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'dart:typed_data';


class VideoRequestPage extends StatefulWidget {
  const VideoRequestPage({Key? key}) : super(key: key);

  @override
  State<VideoRequestPage> createState() => _VideoRequestPageState();
}

class _VideoRequestPageState extends State<VideoRequestPage> {
  var _tx;

  late Data data;

  @override
  Widget build(BuildContext context) {
    data = ModalRoute.of(context)!.settings.arguments as Data;

    sendTxViaMetamask();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tx sending page.'),
      ),
      body: Center(
        child: Column(
          children: [
            Text('TX ID: ${_tx}'),
            Text('Wallet: ${data.connector!.session.accounts[0]}'),
          ],
        )
      ),
    );;
  }

  toHex(int value, {padding=64}) {
    return value.toRadixString(16).padLeft(padding, '0');
  }

  Future<DeployedContract> getContract() async {
    print('trying to load contract');
    String abi = await rootBundle.loadString("assets/contracts/VideoRequester.json");
    print('contract loaded');
    String contractAddress = "0xe011eA99393AaB86E59fd57Ff4DbB48825E36290";
    String contractName = "VideoRequester";

    DeployedContract contract = DeployedContract(
      ContractAbi.fromJson(abi, contractName),
      EthereumAddress.fromHex(contractAddress),
    );

    print('deployed contract created');

    return contract;
  }

  sendTxViaMetamask() async {
      if (data.connector!.connected && _tx == null) {
        try {
          print("Sending transaction");

          // data.request = VideoRequestData(
          //   direction: data.currentPosition!.heading, // sbould be median direction
          //   latitude: data.currentPosition!.latitude,
          //   longitude: data.currentPosition!.longitude,
          //   startTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          //   secondsDuration: 60,
          // );

          print(data.request!.getIntegerDirection());
          print(data.request!.getIntegerLatitude());
          print(data.request!.getIntegerLongitude());
          print(data.request!.startTimestamp);
          print(data.request!.getIntegerEndTimestamp());

          var function_address = 'd8484ca7';
          var requestId = 1;
          var contractAddress = '0xa8cbf99c7ea18a8e6a2ea34619609a0aa9e77211';

          DeployedContract contract = await getContract();
          ContractFunction function = contract.function("submitRequest");

          print('constracting data');
          var data_bytes = function.encodeCall([
              "1",
              BigInt.from(data.request!.getIntegerLatitude()),
              BigInt.from(data.request!.getIntegerLongitude()),
              BigInt.from(data.request!.startTimestamp),
              BigInt.from(data.request!.getIntegerEndTimestamp()),
              BigInt.from(data.request!.getIntegerDirection()),
          ]);
          print(data_bytes);

          EthereumWalletConnectProvider provider = EthereumWalletConnectProvider(data.connector!, chainId: 5);
          launchUrlString(data.connectionUri!, mode: LaunchMode.externalApplication);

          var tx = await provider.sendTransaction(
            from: data.connector!.session.accounts[0],
            to: contractAddress,
            value: EtherAmount.fromUnitAndValue(EtherUnit.finney, BigInt.from(1)).getInWei,
            gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, BigInt.from(100)).getInWei, // get gas price estimation from somewhere.
            gas: 150000, // default: 90000
            data: data_bytes,
          );

          print(tx);
          setState(() {
            data.request!.txHash = tx;
            _tx = tx;
          });
        } catch (exp) {
          print("Error while sending transaction");
          print(exp);
          print(exp.toString());
        }
      }
  }
}
