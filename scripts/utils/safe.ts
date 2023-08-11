import {
  SafeTransactionDataPartial,
  OperationType,
} from '@safe-global/safe-core-sdk-types';
import Safe, { EthersAdapter } from '@safe-global/protocol-kit';
import SafeApiKit from '@safe-global/api-kit';
import { BigNumber, PopulatedTransaction } from 'ethers';
import { ethers } from 'hardhat';
import { Provider } from '@ethersproject/providers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

/**
 * Sends a transaction proposal to the `safeAddress`
 *
 * @param safeAddress - The Safe Multi-sig address
 * @param target - The targeted address of the proposal
 * @param data - The transaction proposal calldata
 * @param isCall - Whether the transaction is a call or delegate call
 * @param msgValue - The transaction msg.value
 */
export async function proposeTransaction(
  safeAddress: string,
  target: string,
  data: string,
  isCall: boolean = true,
  msgValue: BigNumber = BigNumber.from(0),
) {
  const [proposer] = await ethers.getSigners();
  const provider = proposer.provider as Provider;

  const ethAdapter = new EthersAdapter({
    ethers,
    signerOrProvider: proposer,
  });

  // Initialize the Safe Protocol Kit
  const safeSdk = await Safe.create({
    ethAdapter,
    safeAddress,
  });

  const safeTransactionData: SafeTransactionDataPartial = {
    to: target,
    data,
    value: msgValue.toString(),
    operation: isCall ? OperationType.Call : OperationType.DelegateCall,
  };

  // Create a Safe transaction with the provided parameters
  const safeTransaction = await safeSdk.createTransaction({
    safeTransactionData,
  });

  // Deterministic hash based on transaction parameters
  const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);

  // Sign transaction to verify that the transaction is coming from proposer
  const signature = await safeSdk.signTransactionHash(safeTxHash);

  // Initialize the Safe API Kit
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
 * Propose transaction to `safeAddress` or send to contract directly
 *
 * @param propose - Whether to propose the transaction or send it directly
 * @param safeAddress - The Safe Multi-sig address
 * @param signer - The transaction signer
 * @param transaction - The transaction to propose or send
 */
export async function proposeOrSendTransaction(
  propose: boolean,
  safeAddress: string,
  signer: SignerWithAddress,
  transaction: PopulatedTransaction,
) {
  if (propose) {
    await proposeTransaction(
      safeAddress,
      transaction.to as string,
      transaction.data as string,
    );
  } else {
    await signer.sendTransaction(transaction);
  }
}
