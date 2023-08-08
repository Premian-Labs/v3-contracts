export interface ContractAddresses {
  tokens: { [symbol: string]: string };
  vaults: { [name: string]: string };
  optionPS: { [name: string]: string };
  optionReward: { [name: string]: string };
  feeReceiver: string;

  ChainlinkAdapterImplementation: ContractDeploymentInfos;
  ChainlinkAdapterProxy: ContractDeploymentInfos;
  PremiaDiamond: ContractDeploymentInfos;
  PoolFactoryImplementation: ContractDeploymentInfos;
  PoolFactoryProxy: ContractDeploymentInfos;
  PoolFactoryDeployer: ContractDeploymentInfos;
  UserSettingsImplementation: ContractDeploymentInfos;
  UserSettingsProxy: ContractDeploymentInfos;
  ExchangeHelper: ContractDeploymentInfos;
  ReferralImplementation: ContractDeploymentInfos;
  ReferralProxy: ContractDeploymentInfos;
  VxPremiaImplementation: ContractDeploymentInfos;
  VxPremiaProxy: ContractDeploymentInfos;
  ERC20Router: ContractDeploymentInfos;
  PoolBase: ContractDeploymentInfos;
  PoolCore: ContractDeploymentInfos;
  PoolTrade: ContractDeploymentInfos;
  OrderbookStream: ContractDeploymentInfos;
  VaultRegistryImplementation: ContractDeploymentInfos;
  VaultRegistryProxy: ContractDeploymentInfos;
  VolatilityOracleImplementation: ContractDeploymentInfos;
  VolatilityOracleProxy: ContractDeploymentInfos;
  UnderwriterVaultImplementation: ContractDeploymentInfos;
  VaultMiningImplementation: ContractDeploymentInfos;
  VaultMiningProxy: ContractDeploymentInfos;
  OptionPSFactoryImplementation: ContractDeploymentInfos;
  OptionPSFactoryProxy: ContractDeploymentInfos;
  OptionPSImplementation: ContractDeploymentInfos;
  OptionRewardFactoryImplementation: ContractDeploymentInfos;
  OptionRewardFactoryProxy: ContractDeploymentInfos;
  OptionRewardImplementation: ContractDeploymentInfos;
}

export interface ContractDeploymentInfos {
  address: string;
  contractType: ContractType;
  deploymentArgs: string[];
  commitHash: string;
  txHash: string;
  block: number;
  timestamp: number;
}

export enum ContractType {
  Standalone = 'Standalone',
  Proxy = 'Proxy',
  Implementation = 'Implementation',
  DiamondProxy = 'DiamondProxy',
  DiamondFacet = 'DiamondFacet',
}

export enum ChainID {
  Goerli = 5,
  Arbitrum = 42161,
  ArbitrumGoerli = 421613,
}
