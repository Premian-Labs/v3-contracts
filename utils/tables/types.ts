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

export const NameOverride: { [key: string]: string } = {
  PremiaDiamond: 'Premia',
  VxPremiaProxy: 'VxPremiaProxy',
  OptionPSImplementation: 'OptionPS',
  OptionPSFactoryImplementation: 'OptionPSFactory',
  ReferralProxy: 'ReferralProxy',
  VaultMiningProxy: 'VaultMiningProxy',
  PoolFactoryProxy: 'PoolFactoryProxy',
  OptionPSFactoryProxy: 'ProxyUpgradeableOwnable',
  ChainlinkAdapterProxy: 'ProxyUpgradeableOwnable',
  UserSettingsProxy: 'ProxyUpgradeableOwnable',
  VaultRegistryProxy: 'ProxyUpgradeableOwnable',
  VolatilityOracleProxy: 'ProxyUpgradeableOwnable',
  OptionRewardFactoryProxy: 'ProxyUpgradeableOwnable',
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
