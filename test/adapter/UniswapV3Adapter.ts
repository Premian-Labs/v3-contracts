import {
  IUniswapV3Factory__factory,
  IUniswapV3Pool__factory,
  UniswapV3Adapter,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
} from '../../typechain';
import { UNISWAP_V3_FACTORY, Token, tokens } from '../../utils/addresses';
import { ONE_ETHER } from '../../utils/constants';
import {
  convertPriceToBigNumberWithDecimals,
  getPriceBetweenTokens,
  validateQuote,
} from '../../utils/defillama';
import { increase, resetHardhat, setHardhat } from '../../utils/time';
import { AdapterType } from '../../utils/sdk/types';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { bnToAddress } from '@solidstate/library';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';

const target = 1676016000; // Fri Feb 10 2023 08:00:00 GMT+0000
const period = 600;
const cardinalityPerMinute = 4;

let pools: { tokenIn: Token; tokenOut: Token }[];

// prettier-ignore
{
  pools = [
    {tokenIn: tokens.WETH, tokenOut: tokens.WBTC}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.WETH, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.WETH, tokenOut: tokens.DAI}, 
    {tokenIn: tokens.MKR, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.BOND, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.DAI, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.FXS, tokenOut: tokens.FRAX}, 
    {tokenIn: tokens.FRAX, tokenOut: tokens.FXS}, 
    {tokenIn: tokens.FRAX, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.UNI, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.LINK, tokenOut: tokens.UNI}, 
    {tokenIn: tokens.MATIC, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.MATIC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.DAI, tokenOut: tokens.USDT}, 
  ]
}

describe('UniswapV3Adapter', () => {
  async function deploy() {
    const [deployer, notOwner] = await ethers.getSigners();

    const implementation = await new UniswapV3Adapter__factory(deployer).deploy(
      UNISWAP_V3_FACTORY,
      tokens.WETH.address,
      22250,
      30000,
    );

    await implementation.deployed();

    const proxy = await new UniswapV3AdapterProxy__factory(deployer).deploy(
      period,
      cardinalityPerMinute,
      implementation.address,
    );

    await proxy.deployed();

    const instance = UniswapV3Adapter__factory.connect(proxy.address, deployer);

    return { deployer, instance, notOwner };
  }

  async function deployAtBlock() {
    return { ...(await deploy()) };
  }

  describe('#upsertPair', () => {
    it('should revert if there is not enough gas to increase cardinality', async () => {
      const { instance } = await loadFixture(deploy);

      await instance.setCardinalityPerMinute(200);

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.USDC.address, {
          gasLimit: 200000,
        }),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__ObservationCardinalityTooLow',
      );
    });
  });

  for (let i = 0; i < pools.length; i++) {
    const { tokenIn, tokenOut } = pools[i];
    let instance: UniswapV3Adapter;

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

  describe('#quoteFrom', () => {
    before(async () => {
      await setHardhat(
        `https://eth-mainnet.alchemyapi.io/v2/${process.env.API_KEY_ALCHEMY}`,
        16597040,
      );
    });

    after(async () => {
      await resetHardhat();
    });

    it('should revert if the oldest observation is less the TWAP period', async () => {
      const { instance } = await loadFixture(deployAtBlock);

      await instance.upsertPair(tokens.UNI.address, tokens.AAVE.address);

      await expect(
        instance.quoteFrom(tokens.UNI.address, tokens.AAVE.address, target),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__InsufficientObservationPeriod',
      );

      // oldest observation is ~490 seconds
      // fast-forward so that the oldest observation is >= 600 seconds
      await increase(120);

      expect(
        await instance.quoteFrom(
          tokens.UNI.address,
          tokens.AAVE.address,
          target,
        ),
      );
    });
  });
});
