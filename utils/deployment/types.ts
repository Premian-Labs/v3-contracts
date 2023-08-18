export interface DeploymentMetadata {
  addresses: { treasury: string; insuranceFund: string; lzEndpoint: string };
  tokens: { [symbol: string]: string };

  feeConverter: {
    main: ContractDeploymentMetadata;
    insuranceFund: ContractDeploymentMetadata;
  };
  optionPS: { [name: string]: ContractDeploymentMetadata };
  optionReward: { [name: string]: ContractDeploymentMetadata };
  vaults: { [name: string]: ContractDeploymentMetadata };

  ChainlinkAdapterImplementation: ContractDeploymentMetadata;
  ChainlinkAdapterProxy: ContractDeploymentMetadata;
  PremiaDiamond: ContractDeploymentMetadata;
  PoolFactoryImplementation: ContractDeploymentMetadata;
  PoolFactoryProxy: ContractDeploymentMetadata;
  PoolFactoryDeployer: ContractDeploymentMetadata;
  UserSettingsImplementation: ContractDeploymentMetadata;
  UserSettingsProxy: ContractDeploymentMetadata;
  ExchangeHelper: ContractDeploymentMetadata;
  ReferralImplementation: ContractDeploymentMetadata;
  ReferralProxy: ContractDeploymentMetadata;
  VxPremiaImplementation: ContractDeploymentMetadata;
  VxPremiaProxy: ContractDeploymentMetadata;
  ERC20Router: ContractDeploymentMetadata;
  PoolBase: ContractDeploymentMetadata;
  PoolCore: ContractDeploymentMetadata;
  PoolDepositWithdraw: ContractDeploymentMetadata;
  PoolTrade: ContractDeploymentMetadata;
  OrderbookStream: ContractDeploymentMetadata;
  VaultRegistryImplementation: ContractDeploymentMetadata;
  VaultRegistryProxy: ContractDeploymentMetadata;
  VolatilityOracleImplementation: ContractDeploymentMetadata;
  VolatilityOracleProxy: ContractDeploymentMetadata;
  OptionMathExternal: ContractDeploymentMetadata;
  UnderwriterVaultImplementation: ContractDeploymentMetadata;
  VaultMiningImplementation: ContractDeploymentMetadata;
  VaultMiningProxy: ContractDeploymentMetadata;
  OptionPSFactoryImplementation: ContractDeploymentMetadata;
  OptionPSFactoryProxy: ContractDeploymentMetadata;
  OptionPSImplementation: ContractDeploymentMetadata;
  OptionRewardFactoryImplementation: ContractDeploymentMetadata;
  OptionRewardFactoryProxy: ContractDeploymentMetadata;
  OptionRewardImplementation: ContractDeploymentMetadata;
  FeeConverterImplementation: ContractDeploymentMetadata;
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
  [ChainID.ArbitrumGoerli]: 'https://goerli.arbiscan.io/',
  [ChainID.ArbitrumNova]: 'https://nova.arbiscan.io/',
};

export const DeploymentPath: { [chainId: number]: string } = {
  [ChainID.Arbitrum]: 'utils/deployment/arbitrum/',
  [ChainID.ArbitrumGoerli]: 'utils/deployment/arbitrumGoerli/',
  [ChainID.ArbitrumNova]: 'utils/deployment/arbitrumNova/',
};
