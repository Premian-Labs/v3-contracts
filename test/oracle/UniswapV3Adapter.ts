import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  IUniswapV3Pool__factory,
  UniswapV3Adapter,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
} from '../../typechain';

import {
  convertPriceToBigNumberWithDecimals,
  getPrice,
} from '../../utils/defillama';

import { ONE_ETHER } from '../../utils/constants';
import { now } from '../../utils/time';
import { UNISWAP_V3_FACTORY, Token, tokens } from '../../utils/addresses';

import { bnToAddress } from '@solidstate/library';

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 16598000; // Fri Feb 10 2023 09:35:59 GMT+0000
const target = 1676016000; // Fri Feb 10 2023 08:00:00 GMT+0000

let pools: { tokenIn: Token; tokenOut: Token }[];

// prettier-ignore
{
  pools = [
    {tokenIn: tokens.WETH, tokenOut: tokens.WBTC}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.WETH, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.USDC, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.WETH, tokenOut: tokens.DAI}, 
    {tokenIn: tokens.MKR, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.UNI, tokenOut: tokens.AAVE}, 
    {tokenIn: tokens.BOND, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.DAI, tokenOut: tokens.USDC}, 
  ]
}

describe('UniswapV3Adapter', () => {
  let deployer: SignerWithAddress;
  let instance: UniswapV3Adapter;

  before(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);
  });

  beforeEach(async () => {
    [deployer] = await ethers.getSigners();

    const implementation = await new UniswapV3Adapter__factory(deployer).deploy(
      UNISWAP_V3_FACTORY,
    );

    await implementation.deployed();

    const proxy = await new UniswapV3AdapterProxy__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    instance = UniswapV3Adapter__factory.connect(proxy.address, deployer);

    await instance.setPeriod(600);
    await instance.setCardinalityPerMinute(4);
  });

  describe('#isPairSupported', () => {
    it('should return false if pair is not supported by adapter', async () => {
      const [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.false;
    });

    it('should return false if path for pair does not exist', async () => {
      const [_, hasPath] = await instance.isPairSupported(
        tokens.WETH.address,
        bnToAddress(BigNumber.from(0)),
      );

      expect(hasPath).to.be.false;
    });
  });

  describe('#upsertPair', () => {
    it('should revert if pair cannot be supported', async () => {
      await expect(
        instance.upsertPair(
          bnToAddress(BigNumber.from(0)),
          tokens.WETH.address,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );

      await expect(
        instance.upsertPair(
          tokens.WBTC.address,
          bnToAddress(BigNumber.from(0)),
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );
    });

    it('should not fail if called multiple times for same pair', async () => {
      await instance.upsertPair(tokens.WETH.address, tokens.DAI.address);

      const [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.true;

      expect(
        await instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      );
    });
  });

  describe('#quote', async () => {
    it('should revert if pair is not supported', async () => {
      await expect(
        instance.quote(tokens.WETH.address, bnToAddress(BigNumber.from(0))),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairNotSupported',
      );
    });

    it('should revert if observation cardinality must be increased', async () => {
      await instance.setCardinalityPerMinute(20);

      await expect(
        instance.quote(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__ObservationCardinalityTooLow',
      );
    });

    it('should find path if pair has not been added', async () => {
      // must increase cardinality to 121 for pools
      await IUniswapV3Pool__factory.connect(
        '0xc2e9f25be6257c210d7adf0d4cd6e3e881ba25f8',
        deployer,
      ).increaseObservationCardinalityNext(121);

      await IUniswapV3Pool__factory.connect(
        '0x60594a405d53811d3bc4766596efd80fd545a270',
        deployer,
      ).increaseObservationCardinalityNext(121);

      await IUniswapV3Pool__factory.connect(
        '0xa80964c5bbd1a0e95777094420555fead1a26c1e',
        deployer,
      ).increaseObservationCardinalityNext(121);

      expect(await instance.quote(tokens.WETH.address, tokens.DAI.address));
    });

    it('should return quote using correct denomination', async () => {
      let tokenIn = tokens.WETH;
      let tokenOut = tokens.DAI;

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      let quote = await instance.quote(tokenIn.address, tokenOut.address);

      let invertedQuote = await instance.quote(
        tokenOut.address,
        tokenIn.address,
      );

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));

      tokenIn = tokens.WETH;
      tokenOut = tokens.USDC;

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      quote = await instance.quote(tokenIn.address, tokenOut.address);
      invertedQuote = await instance.quote(tokenOut.address, tokenIn.address);

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));

      tokenIn = tokens.WBTC;
      tokenOut = tokens.USDC;

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      quote = await instance.quote(tokenIn.address, tokenOut.address);
      invertedQuote = await instance.quote(tokenOut.address, tokenIn.address);

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));
    });
  });

  // TODO:
  describe.skip('#quoteFrom', () => {});
  describe.skip('#supportedFeeTiers', () => {});
  describe.skip('#poolsForPair', () => {});
  describe.skip('#setPeriod', () => {});
  describe.skip('#setCardinalityPerMinute', () => {});
  describe.skip('#setGasPerCardinality', () => {});
  describe.skip('#setGasCostToSupportPool', () => {});
  describe.skip('#insertFeeTier', () => {});

  for (let i = 0; i < pools.length; i++) {
    const { tokenIn, tokenOut } = pools[i];

    describe(`${tokenIn.symbol}-${tokenOut.symbol}`, () => {
      beforeEach(async () => {
        await instance.upsertPair(tokenIn.address, tokenOut.address);
      });

      describe('#isPairSupported', () => {
        it('should return true if pair is cached and path exists', async () => {
          const [isCached, hasPath] = await instance.isPairSupported(
            tokenIn.address,
            tokenOut.address,
          );

          expect(isCached).to.be.true;
          expect(hasPath).to.be.true;
        });
      });

      describe('#quote', async () => {
        it('should return quote for pair', async () => {
          let _tokenIn = Object.assign({}, tokenIn);
          let _tokenOut = Object.assign({}, tokenOut);

          let networks = { tokenIn: 'ethereum', tokenOut: 'ethereum' };

          const quote = await instance.quote(
            _tokenIn.address,
            _tokenOut.address,
          );

          if (tokenIn.symbol === tokens.CHAINLINK_ETH.symbol) {
            networks.tokenIn = 'coingecko';
            _tokenIn.address = 'ethereum';
          }

          if (tokenOut.symbol === tokens.CHAINLINK_ETH.symbol) {
            networks.tokenOut = 'coingecko';
            _tokenOut.address = 'ethereum';
          }

          if (tokenIn.symbol === tokens.CHAINLINK_BTC.symbol) {
            networks.tokenIn = 'coingecko';
            _tokenIn.address = 'bitcoin';
          }

          if (tokenOut.symbol === tokens.CHAINLINK_BTC.symbol) {
            networks.tokenOut = 'coingecko';
            _tokenOut.address = 'bitcoin';
          }

          const coingeckoPrice = await getPriceBetweenTokens(
            networks,
            _tokenIn,
            _tokenOut,
          );

          const expected = convertPriceToBigNumberWithDecimals(
            coingeckoPrice,
            18,
          );

          validateQuote(quote, expected);
        });
      });

      describe.skip('#quoteFrom', async () => {
        it('should return quote for pair from target', async () => {
          // although the adapter will attepmt to return the price closest to the target
          // the time of the update will likely be before or after the target.
          TRESHOLD_PERCENTAGE = 40;

          let _tokenIn = Object.assign({}, tokenIn);
          let _tokenOut = Object.assign({}, tokenOut);

          let networks = { tokenIn: 'ethereum', tokenOut: 'ethereum' };

          const quoteFrom = await instance.quoteFrom(
            _tokenIn.address,
            _tokenOut.address,
            target,
          );

          if (tokenIn.symbol === tokens.CHAINLINK_ETH.symbol) {
            networks.tokenIn = 'coingecko';
            _tokenIn.address = 'ethereum';
          }

          if (tokenOut.symbol === tokens.CHAINLINK_ETH.symbol) {
            networks.tokenOut = 'coingecko';
            _tokenOut.address = 'ethereum';
          }

          if (tokenIn.symbol === tokens.CHAINLINK_BTC.symbol) {
            networks.tokenIn = 'coingecko';
            _tokenIn.address = 'bitcoin';
          }

          if (tokenOut.symbol === tokens.CHAINLINK_BTC.symbol) {
            networks.tokenOut = 'coingecko';
            _tokenOut.address = 'bitcoin';
          }

          const coingeckoPrice = await getPriceBetweenTokens(
            networks,
            _tokenIn,
            _tokenOut,
            target,
          );

          const expected = convertPriceToBigNumberWithDecimals(
            coingeckoPrice,
            18,
          );

          validateQuote(quoteFrom, expected);
        });
      });
    });
  }
});

// TODO: move to separate file
let TRESHOLD_PERCENTAGE = 2; // 2%

function validateQuote(quote: BigNumber, expected: BigNumber) {
  const threshold = expected.mul(TRESHOLD_PERCENTAGE * 10).div(100 * 10);
  const [upperThreshold, lowerThreshold] = [
    expected.add(threshold),
    expected.sub(threshold),
  ];
  const diff = quote.sub(expected);
  const sign = diff.isNegative() ? '-' : '+';
  const diffPercentage = diff.abs().mul(10000).div(expected).toNumber() / 100;

  expect(
    quote.lte(upperThreshold) && quote.gte(lowerThreshold),
    `Expected ${quote.toString()} to be within [${lowerThreshold.toString()},${upperThreshold.toString()}]. Diff was ${sign}${diffPercentage}%`,
  ).to.be.true;
}

async function getPriceBetweenTokens(
  networks: { tokenIn: string; tokenOut: string },
  tokenIn: Token,
  tokenOut: Token,
  target: number = 0,
) {
  if (tokenIn.address === tokens.CHAINLINK_USD.address) {
    return 1 / (await fetchPrice(networks.tokenOut, tokenOut.address, target));
  }
  if (tokenOut.address === tokens.CHAINLINK_USD.address) {
    return await fetchPrice(networks.tokenIn, tokenIn.address, target);
  }

  let tokenInPrice = await fetchPrice(
    networks.tokenIn,
    tokenIn.address,
    target,
  );
  let tokenOutPrice = await fetchPrice(
    networks.tokenOut,
    tokenOut.address,
    target,
  );

  return tokenInPrice / tokenOutPrice;
}

let cache: { [address: string]: { [target: number]: number } } = {};

async function fetchPrice(
  network: string,
  address: string,
  target: number = 0,
): Promise<number> {
  if (!cache[address]) cache[address] = {};
  if (!cache[address][target]) {
    if (target == 0) target = await now();
    const price = await getPrice(network, address, target);
    cache[address][target] = price;
  }
  return cache[address][target];
}
