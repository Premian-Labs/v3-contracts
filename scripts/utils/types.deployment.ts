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
  rewardDistributor: { [name: string]: ContractDeploymentMetadata };
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
