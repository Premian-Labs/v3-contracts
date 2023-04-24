import { BigNumber } from 'ethers';

export enum AdapterType {
  NONE,
  CHAINLINK,
  UNISWAP_V3,
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

export interface QuoteRFQ {
  provider: string;
  taker: string;
  price: BigNumber;
  size: BigNumber;
  isBuy: boolean;
  deadline: BigNumber;
  salt: BigNumber;
}
