export interface ContractAddresses {
  tokens: { [symbol: string]: string };
  vaults: { [name: string]: string };
  feeReceiver: string;

  ChainlinkAdapterImplementation: string;
  ChainlinkAdapterProxy: string;
  PremiaDiamond: string;
  PoolFactoryImplementation: string;
  PoolFactoryProxy: string;
  PoolFactoryDeployer: string;
  UserSettingsImplementation: string;
  UserSettingsProxy: string;
  ExchangeHelper: string;
  ReferralImplementation: string;
  ReferralProxy: string;
  VxPremiaImplementation: string;
  VxPremiaProxy: string;
  ERC20Router: string;
  PoolBase: string;
  PoolCore: string;
  PoolTrade: string;
  OrderbookStream: string;
  VaultRegistryImplementation: string;
  VaultRegistryProxy: string;
  VolatilityOracleImplementation: string;
  VolatilityOracleProxy: string;
  UnderwriterVaultImplementation: string;
}

export enum ChainID {
  Goerli = 5,
  Arbitrum = 42161,
  ArbitrumGoerli = 421613,
}
