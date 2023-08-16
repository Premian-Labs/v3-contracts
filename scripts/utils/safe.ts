import {
  MetaTransactionData,
  OperationType,
} from '@safe-global/safe-core-sdk-types';
import Safe, { EthersAdapter } from '@safe-global/protocol-kit';
import SafeApiKit from '@safe-global/api-kit';
import { BigNumber, PopulatedTransaction } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { SafeChainPrefix } from '../../utils/deployment/types';
import {
  getNetwork,
  getTransactionUrl,
} from '../../utils/deployment/deployment';

/**
 * Sends a Safe transaction proposal to the `safeAddress`
 *
 * @param safeAddress - The Safe Multi-sig address
 * @param proposer - The Safe transaction proposer
 * @param safeTransactionData - The Safe transaction data
 * @param logSafeTxUrl - If true, log the Safe transaction queue URL
 */
export async function proposeSafeTransaction(
  safeAddress: string,
  proposer: SignerWithAddress,
  safeTransactionData: MetaTransactionData[],
  logSafeTxUrl = false,
) {
  const ethAdapter = new EthersAdapter({
    ethers,
    signerOrProvider: proposer,
  });

  // Initialize the Safe Protocol Kit
  const safeSdk = await Safe.create({
    ethAdapter,
    safeAddress,
  });

  // Create a Safe transaction with the provided parameters
  const safeTransaction = await safeSdk.createTransaction({
    safeTransactionData,
  });

  // Deterministic hash based on transaction parameters
  const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);

  // Sign transaction to verify that the transaction is coming from proposer
  const signature = await safeSdk.signTransactionHash(safeTxHash);

  // Initialize the Safe API Kit
  const network = await getNetwork(proposer);
  const safeService = new SafeApiKit({
    txServiceUrl: `https://safe-transaction-${network.name}.safe.global`,
    ethAdapter,
  });

  // Propose transaction hash
  await safeService.proposeTransaction({
    safeAddress,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: proposer.address,
    senderSignature: signature.data,
  });

  if (logSafeTxUrl) {
    console.log(
      `Transaction proposed to Safe: https://app.safe.global/transactions/queue?safe=${
        SafeChainPrefix[network.chainId]
      }:${safeAddress}`,
    );
  }
}

/**
 * Propose Safe transaction to `safeAddress` or send to contract directly
 *
 * @param propose - Whether to propose the transaction or send it directly
 * @param safeAddress - The Safe Multi-sig address
 * @param signer - The transaction signer
 * @param transactions - The list of transactions to propose or send
 * @param logTxUrl - If true, log the Safe transaction queue or transaction URL
 */
export async function proposeOrSendTransaction(
  propose: boolean,
  safeAddress: string,
  signer: SignerWithAddress,
  transactions: PopulatedTransaction[],
  logTxUrl = false,
) {
  if (propose) {
    const safeTransactionData = [];

    for (let transaction of transactions) {
      safeTransactionData.push({
        to: transaction.to as string,
        data: transaction.data as string,
        value: transaction.value?.toString() ?? BigNumber.from(0).toString(),
        operation: OperationType.Call,
      });
    }

    await proposeSafeTransaction(safeAddress, signer, safeTransactionData);
  } else {
    let m = 1;
    const n = transactions.length;

    for (let transaction of transactions) {
      const tx = await signer.sendTransaction(transaction);
      await tx.wait();

      if (logTxUrl) {
        const transactionUrl = await getTransactionUrl(tx.hash, signer);
        console.log(
          n > 1
            ? `${m} of ${n} transactions executed: ${tx.hash} (${transactionUrl})`
            : `Transaction executed: ${tx.hash} (${transactionUrl})`,
        );
      }

      ++m;
    }
  }
}
