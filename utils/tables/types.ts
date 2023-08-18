import { ContractType } from '../deployment/types';

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
  type?: ContractType;
  address: string;
  commitHash?: string;
  etherscanUrl: string;
  filePath?: string;
  displayAddress: () => string;
  displayEtherscanUrl: () => string;
  displayFilePathUrl?: () => string;
};

export const DescriptionOverride: { [key: string]: string } = {
  PremiaDiamond: 'Premia Diamond Proxy',
  VxPremiaImplementation: 'vxPREMIA Implementation',
  VxPremiaProxy: 'vxPREMIA Proxy',
  OptionPSImplementation: 'Option Physically Settled Implementation',
  OptionPSFactoryImplementation:
    'Option Physically Settled Factory Implementation',
  OptionPSFactoryProxy: 'Option Physically Settled Factory Proxy',
};

export const CoreContractMetaData: { [name: string]: MetaData } = {
  ChainlinkAdapterImplementation: {
    name: 'ChainlinkAdapter',
  },
  ChainlinkAdapterProxy: {
    name: 'ProxyUpgradeableOwnable',
  },
  PremiaDiamond: {
    name: 'Premia',
  },
  PoolFactoryImplementation: {
    name: 'PoolFactory',
  },
  PoolFactoryProxy: {
    name: 'PoolFactoryProxy',
  },
  PoolFactoryDeployer: {
    name: 'PoolFactoryDeployer',
  },
  UserSettingsImplementation: {
    name: 'UserSettings',
  },
  UserSettingsProxy: {
    name: 'ProxyUpgradeableOwnable',
  },
  ExchangeHelper: {
    name: 'ExchangeHelper',
  },
  ReferralImplementation: {
    name: 'Referral',
  },
  ReferralProxy: {
    name: 'ReferralProxy',
  },
  VxPremiaImplementation: {
    name: 'VxPremia',
  },
  VxPremiaProxy: {
    name: 'VxPremiaProxy',
  },
  ERC20Router: {
    name: 'ERC20Router',
  },
  PoolBase: {
    name: 'PoolBase',
  },
  PoolCore: {
    name: 'PoolCore',
  },
  PoolDepositWithdraw: {
    name: 'PoolDepositWithdraw',
  },
  PoolTrade: {
    name: 'PoolTrade',
  },
  OrderbookStream: {
    name: 'OrderbookStream',
  },
  VaultRegistryImplementation: {
    name: 'VaultRegistry',
  },
  VaultRegistryProxy: {
    name: 'ProxyUpgradeableOwnable',
  },
  VolatilityOracleImplementation: {
    name: 'VolatilityOracle',
  },
  VolatilityOracleProxy: {
    name: 'ProxyUpgradeableOwnable',
  },
  OptionMathExternal: {
    name: 'OptionMathExternal',
  },
  UnderwriterVaultImplementation: {
    name: 'UnderwriterVault',
  },
  VaultMiningImplementation: {
    name: 'VaultMining',
  },
  VaultMiningProxy: {
    name: 'VaultMiningProxy',
  },
  OptionPSFactoryImplementation: {
    name: 'OptionPSFactory',
  },
  OptionPSFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
  },
  OptionPSImplementation: {
    name: 'OptionPS',
  },
  OptionRewardFactoryImplementation: {
    name: 'OptionRewardFactory',
  },
  OptionRewardFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
  },
  OptionRewardImplementation: {
    name: 'OptionReward',
  },
  FeeConverterImplementation: {
    name: 'FeeConverter',
  },
};

interface MetaData {
  name: string;
}
