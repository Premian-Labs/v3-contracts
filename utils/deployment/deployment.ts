import fs from 'fs';
import path from 'path';
import child_process from 'child_process';

import { IOwnable__factory } from '../../typechain';
import {
  BlockExplorerUrl,
  ChainID,
  ContractKey,
  ContractType,
  DeploymentMetadata,
  DeploymentPath,
} from './types';
import { Provider } from '@ethersproject/providers';
import { BaseContract } from 'ethers';
import { run } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import _ from 'lodash';
import { Network } from '@ethersproject/networks';
import arbitrumDeployment from './arbitrum/metadata.json';
import arbitrumGoerliDeployment from './arbitrumGoerli/metadata.json';
import { ethers } from 'hardhat';
import { generateTables } from '../tables/model';

export async function initialize(
  providerOrSigner: Provider | SignerWithAddress,
) {
  const network = await getNetwork(providerOrSigner);

  let deployment: DeploymentMetadata;
  let proposeToMultiSig: boolean;
  let proxyManager: string;

  if (network.chainId === ChainID.Arbitrum) {
    proxyManager = '0x89b36CE3491f2258793C7408Bd46aac725973BA2';
    deployment = arbitrumDeployment;
    proposeToMultiSig = true;
  } else if (network.chainId === ChainID.ArbitrumGoerli) {
    proxyManager = ethers.constants.AddressZero;
    deployment = arbitrumGoerliDeployment;
    proposeToMultiSig = false;
  } else {
    throw new Error('ChainId not implemented');
  }

  return { network, deployment, proposeToMultiSig, proxyManager };
}

export async function updateDeploymentMetadata(
  providerOrSigner: Provider | SignerWithAddress,
  objectPath: ContractKey | string,
  contractType: ContractType,
  deployedContract: BaseContract,
  deploymentArgs: string[],
  logTxUrl = false,
  writeFile = true,
  verifyContracts = true,
  libraries: { [key: string]: string } = {},
) {
  const provider = getProvider(providerOrSigner);
  const network = await getNetwork(provider);
  const chainId = network.chainId;
  const metadataJsonPath = DeploymentPath[chainId] + 'metadata.json';

  const data = JSON.parse(
    fs.readFileSync(metadataJsonPath).toString(),
  ) as DeploymentMetadata;

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
    fs.writeFileSync(metadataJsonPath, JSON.stringify(data, undefined, 2));
  }

  if (logTxUrl) {
    const addressUrl = await getAddressUrl(
      deployedContract.address,
      providerOrSigner,
    );

    console.log(
      `Contract deployed: ${deployedContract.address} (${addressUrl})`,
    );
  }

  if (verifyContracts) {
    await verifyContractsOnEtherscan(
      deployedContract,
      deploymentArgs,
      libraries,
    );
  }

  await generateTables(network);

  return data;
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

export async function verifyContractsOnEtherscan(
  contract: BaseContract,
  constructorArguments: any[],
  libraries: any = {},
) {
  await contract.deployed();
  await run('verify:verify', {
    address: contract.address,
    constructorArguments,
    libraries,
  });
}

export function getContractFilePaths(): string[] {
  let contractFilePaths: string[] = [];

  (function _getContractFilePaths(rootPath: string) {
    fs.readdirSync(rootPath).forEach((file) => {
      const absolutePath = path.join(rootPath, file);
      if (fs.statSync(absolutePath).isDirectory())
        return _getContractFilePaths(absolutePath);
      else return contractFilePaths.push(absolutePath);
    });
  })('./contracts');

  return contractFilePaths;
}

export function getContractFilePath(
  contractName: string,
  contractFilePaths: string[],
): string {
  for (const contractFilePath of contractFilePaths) {
    const contractFileNameWithExtension =
      contractFilePath.split('/').pop() ?? '';

    if (contractFileNameWithExtension.length === 0)
      throw Error('Contract file name is empty');

    if (contractFileNameWithExtension.split('.')[0] === contractName)
      return contractFilePath;
  }

  return '';
}
