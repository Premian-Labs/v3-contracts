export interface ContractAddresses {
  tokens: { [symbol: string]: string };
  ChainlinkAdapterImplementation: string;
  ChainlinkAdapterProxy: string;
  InitFeeCalculatorImplementation: string;
  InitFeeCalculatorProxy: string;
  PremiaDiamond: string;
  PoolFactoryImplementation: string;
  PoolFactoryProxy: string;
  ExchangeHelper: string;
  VxPremiaImplementation: string;
  VxPremiaProxy: string;
  ERC20Router: string;
  PoolBase: string;
  PoolCore: string;
  PoolTrade: string;
}

export enum ChainID {
  Goerli = 5,
  Arbitrum = 42161,
  ArbitrumGoerli = 421613,
}
