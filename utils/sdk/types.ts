import { BigNumber } from 'ethers';

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

interface TradeQuoteBase {
  provider: string;
  taker: string;
  price: number | string;
  size: number | string;
  isBuy: boolean;
  category: number;
  deadline: number;
}

export interface TradeQuote extends TradeQuoteBase {
  categoryNonce: number;
}

export interface TradeQuoteNonceOptional extends TradeQuoteBase {
  categoryNonce?: number;
}
