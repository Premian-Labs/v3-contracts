import { BigNumber } from 'ethers';

export enum AdapterType {
  NONE,
  CHAINLINK,
}

export enum TokenType {
  SHORT = 0,
  LONG = 1,
}

export enum OrderType {
  CSUP,
  CS,
  LC,
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
  oracleAdapter: string;
  strike: BigNumber;
  maturity: BigNumber;
  isCallPool: boolean;
}

export interface QuoteOB {
  provider: string;
  taker: string;
  price: BigNumber;
  size: BigNumber;
  isBuy: boolean;
  deadline: BigNumber;
  salt: BigNumber;
}
