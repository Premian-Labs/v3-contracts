import {
  MetaTransactionData,
  OperationType,
} from '@safe-global/safe-core-sdk-types';
import Safe, { EthersAdapter } from '@safe-global/protocol-kit';
import SafeApiKit from '@safe-global/api-kit';
import { BigNumber, PopulatedTransaction } from 'ethers';
import { ethers } from 'hardhat';
import { Provider } from '@ethersproject/providers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

/**
 * Sends a Safe transaction proposal to the `safeAddress`
 *
 * @param safeAddress - The Safe Multi-sig address
 * @param proposer - The Safe transaction proposer
 * @param safeTransactionData - The Safe transaction data
 */
export async function proposeSafeTransaction(
  safeAddress: string,
  proposer: SignerWithAddress,
  safeTransactionData: MetaTransactionData[],
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
  const provider = proposer.provider as Provider;
  const chainName = (await provider.getNetwork()).name;
  const safeService = new SafeApiKit({
    txServiceUrl: `https://safe-transaction-${chainName}.safe.global`,
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
}

/**
 * Propose Safe transaction to `safeAddress` or send to contract directly
 *
 * @param propose - Whether to propose the transaction or send it directly
 * @param safeAddress - The Safe Multi-sig address
 * @param signer - The transaction signer
 * @param transactions - The transactions to propose or send
 * @param isCall - Whether the transaction is a call or delegate call
 */
export async function proposeOrSendTransaction(
  propose: boolean,
  safeAddress: string,
  signer: SignerWithAddress,
  transactions: PopulatedTransaction[],
  isCall: boolean,
) {
  if (propose) {
    const safeTransactionData = [];
    for (let transaction of transactions) {
      safeTransactionData.push({
        to: transaction.to as string,
        data: transaction.data as string,
        value: transaction.value?.toString() ?? BigNumber.from(0).toString(),
        operation: isCall ? OperationType.Call : OperationType.DelegateCall,
      });
    }

    await proposeSafeTransaction(safeAddress, signer, safeTransactionData);
  } else {
    for (let transaction of transactions) {
      await signer.sendTransaction(transaction);
    }
  }
}
