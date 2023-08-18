export interface TableData {
  categories: {
    [key: string]: {
      name: string;
      chain: string;
      sections: Section[];
      displayHeader: () => string;
    };
  };
}

type Section = {
  name: string;
  contracts: Contract[];
};

export type Contract = {
  name: string;
  description: string;
  address: string;
  commitHash?: string;
  etherscanUrl: string;
  filePath?: string;
  displayAddress: () => string;
  displayEtherscanUrl: () => string;
  displayFilePathUrl?: () => string;
};

export const CoreContractMetaData: { [name: string]: MetaData } = {
  ChainlinkAdapterImplementation: {
    name: 'ChainlinkAdapter',
    description: 'Chainlink Adapter Implementation',
  },
  ChainlinkAdapterProxy: {
    name: 'ProxyUpgradeableOwnable',
    description: 'Chainlink Adapter Proxy',
  },
  PremiaDiamond: {
    name: 'Premia',
    description: '',
  },
  PoolFactoryImplementation: {
    name: 'PoolFactory',
    description: '',
  },
  PoolFactoryProxy: {
    name: 'PoolFactoryProxy',
    description: '',
  },
  PoolFactoryDeployer: {
    name: 'PoolFactoryDeployer',
    description: '',
  },
  UserSettingsImplementation: {
    name: 'UserSettings',
    description: '',
  },
  UserSettingsProxy: {
    name: 'ProxyUpgradeableOwnable',
    description: '',
  },
  ExchangeHelper: {
    name: 'ExchangeHelper',
    description: '',
  },
  ReferralImplementation: {
    name: 'Referral',
    description: '',
  },
  ReferralProxy: {
    name: 'ReferralProxy',
    description: '',
  },
  VxPremiaImplementation: {
    name: 'VxPremia',
    description: '',
  },
  VxPremiaProxy: {
    name: 'VxPremiaProxy',
    description: '',
  },
  ERC20Router: {
    name: 'ERC20Router',
    description: '',
  },
  PoolBase: {
    name: 'PoolBase',
    description: '',
  },
  PoolCore: {
    name: 'PoolCore',
    description: '',
  },
  PoolDepositWithdraw: {
    name: 'PoolDepositWithdraw',
    description: '',
  },
  PoolTrade: {
    name: 'PoolTrade',
    description: '',
  },
  OrderbookStream: {
    name: 'OrderbookStream',
    description: '',
  },
  VaultRegistryImplementation: {
    name: 'VaultRegistry',
    description: '',
  },
  VaultRegistryProxy: {
    name: 'ProxyUpgradeableOwnable',
    description: '',
  },
  VolatilityOracleImplementation: {
    name: 'VolatilityOracle',
    description: '',
  },
  VolatilityOracleProxy: {
    name: 'ProxyUpgradeableOwnable',
    description: '',
  },
  OptionMathExternal: {
    name: 'OptionMathExternal',
    description: '',
  },
  UnderwriterVaultImplementation: {
    name: 'UnderwriterVault',
    description: '',
  },
  VaultMiningImplementation: {
    name: 'VaultMining',
    description: '',
  },
  VaultMiningProxy: {
    name: 'VaultMiningProxy',
    description: '',
  },
  OptionPSFactoryImplementation: {
    name: 'OptionPSFactory',
    description: '',
  },
  OptionPSFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
    description: '',
  },
  OptionPSImplementation: {
    name: 'OptionPS',
    description: '',
  },
  OptionRewardFactoryImplementation: {
    name: 'OptionRewardFactory',
    description: '',
  },
  OptionRewardFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
    description: '',
  },
  OptionRewardImplementation: {
    name: 'OptionReward',
    description: '',
  },
  FeeConverterImplementation: {
    name: 'FeeConverter',
    description: '',
  },
};

interface MetaData {
  name: string;
  description: string;
}
