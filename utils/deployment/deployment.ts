import child_process from 'child_process';
import { IOwnable__factory } from '../../typechain';
import {
  BlockExplorerUrl,
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from './types';
import fs from 'fs';
import { Provider } from '@ethersproject/providers';
import { BaseContract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import _ from 'lodash';
import { Network } from '@ethersproject/networks';

export async function updateDeploymentInfos(
  providerOrSigner: Provider | SignerWithAddress,
  objectPath: ContractKey | string,
  contractType: ContractType,
  deployedContract: BaseContract,
  deploymentArgs: string[],
  logTxUrl = false,
  writeFile = true,
) {
  const provider = getProvider(providerOrSigner);
  const chainId = (await getNetwork(provider)).chainId;
  const jsonPath = getDeploymentJsonPath(chainId);

  const data = JSON.parse(
    fs.readFileSync(jsonPath).toString(),
  ) as DeploymentInfos;

  const txReceipt = await deployedContract.deployTransaction.wait();
  let owner = '';

  try {
    const owned = IOwnable__factory.connect(deployedContract.address, provider);
    owner = await owned.owner();
  } catch (e) {}

  _.set(data, objectPath, {
    address: deployedContract.address,
    block: txReceipt.blockNumber,
    commitHash: getCommitHash(),
    contractType,
    deploymentArgs,
    timestamp: await getBlockTimestamp(provider, txReceipt.blockNumber),
    txHash: txReceipt.transactionHash,
    owner: owner,
  });

  if (writeFile) {
    fs.writeFileSync(jsonPath, JSON.stringify(data, undefined, 2));
  }

  if (logTxUrl) {
    const addressUrl = await getAddressUrl(
      deployedContract.address,
      providerOrSigner,
    );

    console.log(`Contract deployed: ${addressUrl}`);
  }

  return data;
}

export function getDeploymentJsonPath(chainId: ChainID) {
  switch (chainId) {
    case ChainID.Arbitrum:
      return 'utils/deployment/arbitrum.json';
    case ChainID.ArbitrumGoerli:
      return 'utils/deployment/arbitrumGoerli.json';
    case ChainID.ArbitrumNova:
      return 'utils/deployment/arbitrumNova.json';
    default:
      throw new Error('ChainId not implemented');
  }
}

export async function getBlockTimestamp(
  provider: Provider,
  blockNumber: number,
) {
  return (await provider.getBlock(blockNumber)).timestamp;
}

export function getCommitHash() {
  return child_process.execSync('git rev-parse HEAD').toString().trim();
}

export async function getTransactionUrl(
  txHash: string,
  providerOrSigner: Provider | SignerWithAddress,
): Promise<string> {
  const network = await getNetwork(providerOrSigner);
  return `${BlockExplorerUrl[network.chainId]}/tx/${txHash}`;
}

export async function getAddressUrl(
  address: string,
  providerOrSigner: Provider | SignerWithAddress,
): Promise<string> {
  const network = await getNetwork(providerOrSigner);
  return `${BlockExplorerUrl[network.chainId]}/address/${address}`;
}

export async function getNetwork(
  providerOrSigner: Provider | SignerWithAddress,
): Promise<Network> {
  const provider = getProvider(providerOrSigner);
  return await provider.getNetwork();
}

export function getProvider(
  providerOrSigner: Provider | SignerWithAddress,
): Provider {
  return (
    (providerOrSigner as SignerWithAddress).provider ??
    (providerOrSigner as Provider)
  );
}
