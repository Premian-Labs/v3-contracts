export interface DeploymentInfos {
  tokens: { [symbol: string]: string };

  feeConverter: {
    main: ContractDeploymentInfos;
    insuranceFund: ContractDeploymentInfos;
  };
  optionPS: { [name: string]: ContractDeploymentInfos };
  optionReward: { [name: string]: ContractDeploymentInfos };
  vaults: { [name: string]: ContractDeploymentInfos };

  treasury: string;
  insuranceFund: string;
  lzEndpoint: string;

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
  PoolDepositWithdraw: ContractDeploymentInfos;
  PoolTrade: ContractDeploymentInfos;
  OrderbookStream: ContractDeploymentInfos;
  VaultRegistryImplementation: ContractDeploymentInfos;
  VaultRegistryProxy: ContractDeploymentInfos;
  VolatilityOracleImplementation: ContractDeploymentInfos;
  VolatilityOracleProxy: ContractDeploymentInfos;
  OptionMathExternal: ContractDeploymentInfos;
  UnderwriterVaultImplementation: ContractDeploymentInfos;
  VaultMiningImplementation: ContractDeploymentInfos;
  VaultMiningProxy: ContractDeploymentInfos;
  OptionPSFactoryImplementation: ContractDeploymentInfos;
  OptionPSFactoryProxy: ContractDeploymentInfos;
  OptionPSImplementation: ContractDeploymentInfos;
  OptionRewardFactoryImplementation: ContractDeploymentInfos;
  OptionRewardFactoryProxy: ContractDeploymentInfos;
  OptionRewardImplementation: ContractDeploymentInfos;
  FeeConverterImplementation: ContractDeploymentInfos;
}

export enum ContractKey {
  ChainlinkAdapterImplementation = 'ChainlinkAdapterImplementation',
  ChainlinkAdapterProxy = 'ChainlinkAdapterProxy',
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
}

export interface ContractDeploymentInfos {
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
  [ChainID.ArbitrumGoerli]: 'https://goerli.arbiscan.io/',
  [ChainID.ArbitrumNova]: 'https://nova.arbiscan.io/',
};

export const DeploymentJsonPath: { [chainId: number]: string } = {
  [ChainID.Arbitrum]: 'utils/deployment/arbitrum.json',
  [ChainID.ArbitrumGoerli]: 'utils/deployment/arbitrumGoerli.json',
  [ChainID.ArbitrumNova]: 'utils/deployment/arbitrumNova.json',
};
