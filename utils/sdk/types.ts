import { BigNumber, BigNumberish } from 'ethers';

export enum TokenType {
  SHORT = 0,
  LONG = 1,
}

export enum OrderType {
  CSUP,
  CS,
  LC,
}

export interface PositionKey {
  owner: string;
  operator: string;
  lower: BigNumber;
  upper: BigNumber;
  orderType: OrderType;
  isCall: boolean;
  strike: BigNumber;
}

export interface PoolKey {
  base: string;
  quote: string;
  baseOracle: string;
  quoteOracle: string;
  strike: BigNumber;
  maturity: BigNumber;
  isCallPool: boolean;
}

export interface TradeQuote {
  provider: string;
  taker: string;
  price: BigNumber;
  size: BigNumber;
  isBuy: boolean;
  deadline: BigNumber;
  salt: BigNumber;
}
