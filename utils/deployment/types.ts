export interface ContractAddresses {
  tokens: { [symbol: string]: string };
  ChainlinkAdapterImplementation: string;
  ChainlinkAdapterProxy: string;
  UniswapV3AdapterImplementation: string;
  UniswapV3AdapterProxy: string;
  UniswapV3ChainlinkAdapterImplementation: string;
  UniswapV3ChainlinkAdapterProxy: string;
  InitFeeCalculatorImplementation: string;
  InitFeeCalculatorProxy: string;
  PremiaDiamond: string;
  PoolFactoryImplementation: string;
  PoolFactoryProxy: string;
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
}

export enum ChainID {
  Goerli = 5,
  Arbitrum = 42161,
  ArbitrumGoerli = 421613,
}
