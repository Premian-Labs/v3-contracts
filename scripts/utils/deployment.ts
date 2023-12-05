import fs from 'fs';
import child_process from 'child_process';

import { IOwnable__factory } from '../../typechain';
import { Provider, TransactionReceipt } from '@ethersproject/providers';
import { BaseContract } from 'ethers';
import { ethers, run } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import _ from 'lodash';
import { Network } from '@ethersproject/networks';
import arbitrumDeployment from '../../deployments/arbitrum/metadata.json';
import arbitrumGoerliDeployment from '../../deployments/arbitrumGoerli/metadata.json';
import { generateTables } from './table';

export interface DeploymentMetadata {
  addresses: {
    treasury: string;
    insuranceFund: string;
    dao: string;
    lzEndpoint: string;
  };
  tokens: { [symbol: string]: string };

  feeConverter: {
    main: ContractDeploymentMetadata;
    insuranceFund: ContractDeploymentMetadata;
    treasury: ContractDeploymentMetadata;
    dao: ContractDeploymentMetadata;
  };
  core: { [key in ContractKey]: ContractDeploymentMetadata };
  dualMining: { [name: string]: ContractDeploymentMetadata };
  optionPS: { [name: string]: ContractDeploymentMetadata };
  optionReward: { [name: string]: ContractDeploymentMetadata };
  vaults: { [name: string]: ContractDeploymentMetadata };
}

export enum ContractKey {
  ChainlinkAdapterImplementation = 'ChainlinkAdapterImplementation',
  ChainlinkAdapterProxy = 'ChainlinkAdapterProxy',
  DualMiningImplementation = 'DualMiningImplementation',
  DualMiningManager = 'DualMiningManager',
  PremiaDiamond = 'PremiaDiamond',
  PoolFactoryImplementation = 'PoolFactoryImplementation',
  PoolFactoryProxy = 'PoolFactoryProxy',
  PoolFactoryDeployer = 'PoolFactoryDeployer',
  UserSettingsImplementation = 'UserSettingsImplementation',
  UserSettingsProxy = 'UserSettingsProxy',
  ExchangeHelper = 'ExchangeHelper',
  ReferralImplementation = 'ReferralImplementation',
  ReferralProxy = 'ReferralProxy',
  VxPremiaImplementation = 'VxPremiaImplementation',
  VxPremiaProxy = 'VxPremiaProxy',
  ERC20Router = 'ERC20Router',
  PoolBase = 'PoolBase',
  PoolCore = 'PoolCore',
  PoolDepositWithdraw = 'PoolDepositWithdraw',
  PoolTrade = 'PoolTrade',
  OrderbookStream = 'OrderbookStream',
  VaultRegistryImplementation = 'VaultRegistryImplementation',
  VaultRegistryProxy = 'VaultRegistryProxy',
  VolatilityOracleImplementation = 'VolatilityOracleImplementation',
  VolatilityOracleProxy = 'VolatilityOracleProxy',
  OptionMathExternal = 'OptionMathExternal',
  UnderwriterVaultImplementation = 'UnderwriterVaultImplementation',
  VaultMiningImplementation = 'VaultMiningImplementation',
  VaultMiningProxy = 'VaultMiningProxy',
  OptionPSFactoryImplementation = 'OptionPSFactoryImplementation',
  OptionPSFactoryProxy = 'OptionPSFactoryProxy',
  OptionPSImplementation = 'OptionPSImplementation',
  OptionRewardFactoryImplementation = 'OptionRewardFactoryImplementation',
  OptionRewardFactoryProxy = 'OptionRewardFactoryProxy',
  OptionRewardImplementation = 'OptionRewardImplementation',
  FeeConverterImplementation = 'FeeConverterImplementation',
  PaymentSplitterImplementation = 'PaymentSplitterImplementation',
  PaymentSplitterProxy = 'PaymentSplitterProxy',
}

export interface ContractDeploymentMetadata {
  address: string;
  contractType: ContractType | string;
  deploymentArgs: string[];
  commitHash: string;
  txHash: string;
  block: number;
  timestamp: number;
  owner: string;
}

export enum ContractType {
  Standalone = 'Standalone',
  Proxy = 'Proxy',
  Implementation = 'Implementation',
  DiamondProxy = 'DiamondProxy',
  DiamondFacet = 'DiamondFacet',
}

export enum ChainID {
  Ethereum = 1,
  Goerli = 5,
  Arbitrum = 42161,
  ArbitrumGoerli = 421613,
  ArbitrumNova = 42170,
}

export const ChainName: { [chainId: number]: string } = {
  [ChainID.Ethereum]: 'Ethereum',
  [ChainID.Goerli]: 'Goerli',
  [ChainID.Arbitrum]: 'Arbitrum',
  [ChainID.ArbitrumGoerli]: 'Arbitrum Goerli',
  [ChainID.ArbitrumNova]: 'Arbitrum Nova',
};

export const SafeChainPrefix: { [chainId: number]: string } = {
  [ChainID.Ethereum]: 'eth',
  [ChainID.Goerli]: 'gor',
  [ChainID.Arbitrum]: 'arb1',
  // Arbitrum Goerli and Arbitrum Nova are currently not supported by Safe https://docs.safe.global/safe-core-api/available-services
};

export const BlockExplorerUrl: { [chainId: number]: string } = {
  [ChainID.Ethereum]: 'https://etherscan.io',
  [ChainID.Goerli]: 'https://goerli.etherscan.io',
  [ChainID.Arbitrum]: 'https://arbiscan.io',
  [ChainID.ArbitrumGoerli]: 'https://goerli.arbiscan.io',
  [ChainID.ArbitrumNova]: 'https://nova.arbiscan.io',
};

export const DeploymentPath: { [chainId: number]: string } = {
  [ChainID.Arbitrum]: 'deployments/arbitrum/',
  [ChainID.ArbitrumGoerli]: 'deployments/arbitrumGoerli/',
  [ChainID.ArbitrumNova]: 'deployments/arbitrumNova/',
};

interface UpdateDeploymentMetadataOptions {
  logTxUrl?: boolean;
  skipWriteFile?: boolean;
  verification?: VerificationOptions;
  txReceipt?: TransactionReceipt;
}

interface VerificationOptions {
  enableVerification?: boolean;
  contract?: string;
  libraries?: { [key: string]: string };
}

export async function initialize(
  providerOrSigner: Provider | SignerWithAddress,
) {
  const network = await getNetwork(providerOrSigner);

  let deployment: DeploymentMetadata = getDeployment(network.chainId);
  let proposeToMultiSig: boolean;
  let proxyManager: string;

  if (network.chainId === ChainID.Arbitrum) {
    proxyManager = '0x89b36CE3491f2258793C7408Bd46aac725973BA2';
    proposeToMultiSig = true;
  } else if (network.chainId === ChainID.ArbitrumGoerli) {
    proxyManager = ethers.constants.AddressZero;
    proposeToMultiSig = false;
  } else {
    throw new Error('ChainId not implemented');
  }

  return { network, deployment, proposeToMultiSig, proxyManager };
}

export function getDeployment(chain: ChainID): DeploymentMetadata {
  if (chain === ChainID.Arbitrum) return arbitrumDeployment;
  if (chain === ChainID.ArbitrumGoerli) return arbitrumGoerliDeployment;
  throw new Error('ChainId not implemented');
}

export async function updateDeploymentMetadata(
  providerOrSigner: Provider | SignerWithAddress,
  objectPath: ContractKey | string,
  contractType: ContractType,
  deployedContract: BaseContract | string,
  deploymentArgs: string[],
  options: UpdateDeploymentMetadataOptions = {},
) {
  if (objectPath in ContractKey) {
    objectPath = 'core.' + objectPath;
  }

  const provider = getProvider(providerOrSigner);
  const network = await getNetwork(provider);
  const chainId = network.chainId;
  const metadataJsonPath = DeploymentPath[chainId] + 'metadata.json';

  const data = JSON.parse(
    fs.readFileSync(metadataJsonPath).toString(),
  ) as DeploymentMetadata;

  let txReceipt = options.txReceipt;
  if (!txReceipt && typeof deployedContract !== 'string') {
    txReceipt = await deployedContract.deployTransaction.wait();
  }

  const contractAddress =
    typeof deployedContract === 'string'
      ? deployedContract
      : deployedContract.address;

  let owner = '';

  try {
    const owned = IOwnable__factory.connect(contractAddress, provider);
    owner = await owned.owner();
  } catch (e) {}

  _.set(data, objectPath, {
    address: contractAddress,
    block: txReceipt?.blockNumber,
    commitHash: getCommitHash(),
    contractType,
    deploymentArgs,
    timestamp: txReceipt
      ? await getBlockTimestamp(provider, txReceipt.blockNumber)
      : undefined,
    txHash: txReceipt?.transactionHash,
    owner: owner,
  });

  if (!options.skipWriteFile) {
    fs.writeFileSync(metadataJsonPath, JSON.stringify(data, undefined, 2));
  }

  if (options.logTxUrl) {
    const addressUrl = await getAddressUrl(contractAddress, providerOrSigner);

    console.log(`${objectPath} deployed: ${contractAddress} (${addressUrl})`);
  }

  if (options.verification?.enableVerification) {
    await verifyContractsOnEtherscan(
      contractAddress,
      deploymentArgs,
      options.verification?.libraries ?? {},
      options.verification?.contract,
    );
  }

  await generateTables(chainId);

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
  address: string,
  constructorArguments: any[],
  libraries: { [key: string]: string } = {},
  contractPath: string | undefined = undefined, // Example : contracts/proxy/ProxyUpgradeableOwnable.sol:ProxyUpgradeableOwnable
) {
  await run('verify:verify', {
    address,
    contract: contractPath,
    constructorArguments,
    libraries,
  });
}
