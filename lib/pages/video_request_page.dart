import 'package:flutter/material.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web3dart/web3dart.dart';
import 'package:flutter/services.dart';

import 'dart:typed_data';


class VideoRequestPage extends StatefulWidget {
  const VideoRequestPage({Key? key}) : super(key: key);

  @override
  State<VideoRequestPage> createState() => _VideoRequestPageState();
}

class _VideoRequestPageState extends State<VideoRequestPage> {
  var connector, _uri, _tx;

  @override
  Widget build(BuildContext context) {
    var args = ModalRoute.of(context)!.settings.arguments as List;
    connector = args[0];
    _uri = args[1];

    print(connector);
    print(_uri);

    sendTxViaMetamask(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tx sending page.'),
      ),
      body: Center(
        child: Column(
          children: [
            Text('TX ID: ${_tx}'),
            Text('Wallet: ${connector.session.accounts[0]}'),
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

  sendTxViaMetamask(BuildContext context) async {
      if (connector.connected && _tx == null) {
        try {
          print("Sending transaction");

          // TODO: get actual values
          // 41.015137
          // 51.191042
          var lat = 41.0151371;
          var long = 51.19104241;

          // using constant precision here, not sure if that's correct.
          var lat_int = (lat * 1000000).toInt();
          var long_int = (long * 1000000).toInt();

          // default is 1 hour.
          var startTime = (DateTime.now().millisecondsSinceEpoch / 1000).toInt();
          var endTime = startTime + 3600;

          var function_address = '4d07fa9f';
          var requestId = 1;

          var data = function_address +
              toHex(lat_int) +
              toHex(long_int) +
              toHex(startTime) +
              toHex(endTime);

          DeployedContract contract = await getContract();
          ContractFunction function = contract.function("submitRequest");

          print('constracting data');
          var data_bytes = function.encodeCall([
              "1", BigInt.from(lat_int), BigInt.from(long_int), BigInt.from(startTime), BigInt.from(endTime)
          ]);
          print(data_bytes);

          // TODO: how to pack abi?
          // var data = '4d07fa9f00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000b000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000006360e67700000000000000000000000000000000000000000000000000000000637028b700000000000000000000000000000000000000000000000000000000000000013100000000000000000000000000000000000000000000000000000000000000';
          // var data_bytes = data.toUint8List();

          EthereumWalletConnectProvider provider = EthereumWalletConnectProvider(connector, chainId: 5);
          launchUrlString(_uri, mode: LaunchMode.externalApplication);

          var tx = await provider.sendTransaction(
            from: connector.session!.accounts[0],
            to: '0xe011ea99393aab86e59fd57ff4dbb48825e36290',
            value: EtherAmount.fromUnitAndValue(EtherUnit.finney, BigInt.from(1)).getInWei,
            gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, BigInt.from(100)).getInWei, // get gas price estimation from somewhere.
            gas: 90000, // default: 90000
            data: data_bytes,
          );

          print(tx);
          setState(() {
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
