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
  displayAddress: () => string;
  displayEtherscanUrl: () => string;
  displayFilePathUrl?: () => string;
};

export const CoreContractMetaData: { [name: string]: MetaData } = {
  ChainlinkAdapterImplementation: {
    name: 'ChainlinkAdapter',
    section: 'Adapter',
    description: 'Chainlink Adapter Implementation',
  },
  ChainlinkAdapterProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Adapter',
    description: 'Chainlink Adapter Proxy',
  },
  PremiaDiamond: {
    name: 'Premia',
    section: 'Premia Core',
    description: '',
  },
  PoolFactoryImplementation: {
    name: 'PoolFactory',
    section: 'Premia Core',
    description: '',
  },
  PoolFactoryProxy: {
    name: 'PoolFactoryProxy',
    section: 'Premia Core',
    description: '',
  },
  PoolFactoryDeployer: {
    name: 'PoolFactoryDeployer',
    section: 'Premia Core',
    description: '',
  },
  UserSettingsImplementation: {
    name: 'UserSettings',
    section: 'Pool Architecture',
    description: '',
  },
  UserSettingsProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Pool Architecture',
    description: '',
  },
  ExchangeHelper: {
    name: 'ExchangeHelper',
    section: 'Pool Architecture',
    description: '',
  },
  ReferralImplementation: {
    name: 'Referral',
    section: 'Pool Architecture',
    description: '',
  },
  ReferralProxy: {
    name: 'ReferralProxy',
    section: 'Pool Architecture',
    description: '',
  },
  VxPremiaImplementation: {
    name: 'VxPremia',
    section: 'Premia Core',
    description: '',
  },
  VxPremiaProxy: {
    name: 'VxPremiaProxy',
    section: 'Premia Core',
    description: '',
  },
  ERC20Router: {
    name: 'ERC20Router',
    section: 'Premia Core',
    description: '',
  },
  PoolBase: {
    name: 'PoolBase',
    section: 'Pool Architecture',
    description: '',
  },
  PoolCore: {
    name: 'PoolCore',
    section: 'Pool Architecture',
    description: '',
  },
  PoolDepositWithdraw: {
    name: 'PoolDepositWithdraw',
    section: 'Pool Architecture',
    description: '',
  },
  PoolTrade: {
    name: 'PoolTrade',
    section: 'Pool Architecture',
    description: '',
  },
  OrderbookStream: {
    name: 'OrderbookStream',
    section: 'Miscellaneous',
    description: '',
  },
  VaultRegistryImplementation: {
    name: 'VaultRegistry',
    section: 'Periphery',
    description: '',
  },
  VaultRegistryProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Periphery',
    description: '',
  },
  VolatilityOracleImplementation: {
    name: 'VolatilityOracle',
    section: 'Periphery',
    description: '',
  },
  VolatilityOracleProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Periphery',
    description: '',
  },
  OptionMathExternal: {
    name: 'OptionMathExternal',
    section: 'Periphery',
    description: '',
  },
  UnderwriterVaultImplementation: {
    name: 'UnderwriterVault',
    section: 'Periphery',
    description: '',
  },
  VaultMiningImplementation: {
    name: 'VaultMining',
    section: 'Periphery',
    description: '',
  },
  VaultMiningProxy: {
    name: 'VaultMiningProxy',
    section: 'Periphery',
    description: '',
  },
  OptionPSFactoryImplementation: {
    name: 'OptionPSFactory',
    section: 'Miscellaneous',
    description: '',
  },
  OptionPSFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Miscellaneous',
    description: '',
  },
  OptionPSImplementation: {
    name: 'OptionPS',
    section: 'Miscellaneous',
    description: '',
  },
  OptionRewardFactoryImplementation: {
    name: 'OptionRewardFactory',
    section: 'Periphery',
    description: '',
  },
  OptionRewardFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Periphery',
    description: '',
  },
  OptionRewardImplementation: {
    name: 'OptionReward',
    section: 'Periphery',
    description: '',
  },
  FeeConverterImplementation: {
    name: 'FeeConverter',
    section: 'Miscellaneous',
    description: '',
  },
};

interface MetaData {
  name: string;
  section: string;
  description: string;
}
