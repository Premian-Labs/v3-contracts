import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
  UniswapV3ChainlinkAdapter,
  UniswapV3ChainlinkAdapter__factory,
} from '../../typechain';
import {
  UNISWAP_V3_FACTORY,
  feeds,
  Token,
  tokens,
} from '../../utils/addresses';
import {
  convertPriceToBigNumberWithDecimals,
  getPriceBetweenTokens,
  validateQuote,
} from '../../utils/defillama';

import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { bnToAddress } from '@solidstate/library';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';

const period = 600;
const cardinalityPerMinute = 4;

const target = 1676016000; // Fri Feb 10 2023 08:00:00 GMT+0000

let pairs: { tokenIn: Token; tokenOut: Token }[];

// prettier-ignore
{
  pairs = [
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.DAI}, 
    {tokenIn: tokens.MKR, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.MKR, tokenOut: tokens.ENS}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.DAI}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.DAI, tokenOut: tokens.USDC},
    {tokenIn: tokens.DAI, tokenOut: tokens.LINK},
    {tokenIn: tokens.UNI, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.LINK, tokenOut: tokens.UNI}, 
    {tokenIn: tokens.MATIC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.BIT, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.GNO, tokenOut: tokens.LINK}, 
    {tokenIn: tokens.LOOKS, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.LOOKS, tokenOut: tokens.WBTC}, 
  ]
}

describe('UniswapV3ChainlinkAdapter', () => {
  async function deploy() {
    const [deployer] = await ethers.getSigners();

    const chainlinkImplementation = await new ChainlinkAdapter__factory(
      deployer,
    ).deploy(tokens.WETH.address, tokens.WBTC.address);

    await chainlinkImplementation.deployed();

    const chainlinkProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(chainlinkImplementation.address);

    await chainlinkProxy.deployed();

    const chainlinkInstance = ChainlinkAdapter__factory.connect(
      chainlinkProxy.address,
      deployer,
    );

    await chainlinkInstance.batchRegisterFeedMappings(feeds);

    const uniswapImplementation = await new UniswapV3Adapter__factory(
      deployer,
    ).deploy(UNISWAP_V3_FACTORY, tokens.WETH.address, 22250, 30000);

    await uniswapImplementation.deployed();

    const uniswapProxy = await new UniswapV3AdapterProxy__factory(
      deployer,
    ).deploy(cardinalityPerMinute, period, uniswapImplementation.address);

    await uniswapProxy.deployed();

    const uniswapInstance = UniswapV3Adapter__factory.connect(
      uniswapProxy.address,
      deployer,
    );

    await uniswapInstance.setPeriod(period);
    await uniswapInstance.setCardinalityPerMinute(cardinalityPerMinute);

    const implementation = await new UniswapV3ChainlinkAdapter__factory(
      deployer,
    ).deploy(chainlinkProxy.address, uniswapProxy.address, tokens.WETH.address);

    await implementation.deployed();

    const proxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    const instance = UniswapV3ChainlinkAdapter__factory.connect(
      proxy.address,
      deployer,
    );

    return { deployer, instance };
  }

  // TODO: Add after merging #146
  describe.skip('#describePricingPath', () => {});

  for (let i = 0; i < pairs.length; i++) {
    const { tokenIn, tokenOut } = pairs[i];
    let instance: UniswapV3ChainlinkAdapter;

    describe(`${tokenIn.symbol}-${tokenOut.symbol}`, () => {
      beforeEach(async () => {
        const f = await loadFixture(deploy);
        instance = f.instance;
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

          const coingeckoPrice = await getPriceBetweenTokens(
            networks,
            _tokenIn,
            _tokenOut,
          );

          const expected = convertPriceToBigNumberWithDecimals(
            coingeckoPrice,
            18,
          );

          validateQuote(2, quote, expected);
        });
      });

      describe('#quoteFrom', async () => {
        it('should return quote for pair from target', async () => {
          let _tokenIn = Object.assign({}, tokenIn);
          let _tokenOut = Object.assign({}, tokenOut);

          let networks = { tokenIn: 'ethereum', tokenOut: 'ethereum' };

          const quoteFrom = await instance.quoteFrom(
            _tokenIn.address,
            _tokenOut.address,
            target,
          );

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

          validateQuote(2, quoteFrom, expected);
        });
      });
    });
  }
});
