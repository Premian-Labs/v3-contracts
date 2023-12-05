import { BigNumber } from 'ethers';

export interface PoolKey {
  base: string;
  quote: string;
  oracleAdapter: string;
  strike: BigNumber;
  maturity: BigNumber;
  isCallPool: boolean;
}

export enum TradeSide {
  BUY = 0,
  SELL = 1,
  BOTH = 2,
}

export enum OptionType {
  CALL = 0,
  PUT = 1,
  BOTH = 2,
}
