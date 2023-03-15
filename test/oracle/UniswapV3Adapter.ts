import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';

import { bnToAddress } from '@solidstate/library';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

import {
  IUniswapV3Factory__factory,
  IUniswapV3Pool__factory,
  UniswapV3Adapter,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
} from '../../typechain';

import {
  convertPriceToBigNumberWithDecimals,
  getPriceBetweenTokens,
  validateQuote,
} from '../../utils/defillama';

import { UNISWAP_V3_FACTORY, Token, tokens } from '../../utils/addresses';
import { ONE_ETHER } from '../../utils/constants';
import { increase, resetHardhat, setHardhat } from '../../utils/time';

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
      22250,
      30000,
    );

    await implementation.deployed();

    const proxy = await new UniswapV3AdapterProxy__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    const instance = UniswapV3Adapter__factory.connect(proxy.address, deployer);

    await instance.setPeriod(period);
    await instance.setCardinalityPerMinute(cardinalityPerMinute);

    return { deployer, instance, notOwner };
  }

  async function deployAtBlock() {
    const [deployer] = await ethers.getSigners();

    const implementation = await new UniswapV3Adapter__factory(deployer).deploy(
      UNISWAP_V3_FACTORY,
      22250,
      30000,
    );

    await implementation.deployed();

    const proxy = await new UniswapV3AdapterProxy__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    const instance = UniswapV3Adapter__factory.connect(proxy.address, deployer);

    await instance.setPeriod(period);
    await instance.setCardinalityPerMinute(cardinalityPerMinute);

    return { deployer, instance };
  }

  describe('#isPairSupported', () => {
    it('should return false if pair is not supported by adapter', async () => {
      const { instance } = await loadFixture(deploy);

      const [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.false;
    });

    it('should return false if path for pair does not exist', async () => {
      const { instance } = await loadFixture(deploy);

      const [_, hasPath] = await instance.isPairSupported(
        tokens.WETH.address,
        bnToAddress(BigNumber.from(0)),
      );

      expect(hasPath).to.be.false;
    });
  });

  describe('#upsertPair', () => {
    it('should revert if pair cannot be supported', async () => {
      const { instance } = await loadFixture(deploy);

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

    it('should revert if gas provided is too low', async () => {
      const { instance } = await loadFixture(deploy);

      await instance.setCardinalityPerMinute(200);

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.USDC.address, {
          gasLimit: 200000,
        }),
      ).to.be.revertedWithCustomError(instance, 'UniswapV3Adapter__GasTooLow');
    });

    it('should not fail if called multiple times for same pair', async () => {
      const { instance } = await loadFixture(deploy);

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

    it('should skip pool(s) if the cardinality is not at target', async () => {
      const { deployer, instance } = await loadFixture(deploy);

      const pool500 = await IUniswapV3Factory__factory.connect(
        UNISWAP_V3_FACTORY,
        deployer,
      ).getPool(tokens.WBTC.address, tokens.USDT.address, 500);

      // most liquid pool
      const pool3000 = await IUniswapV3Factory__factory.connect(
        UNISWAP_V3_FACTORY,
        deployer,
      ).getPool(tokens.WBTC.address, tokens.USDT.address, 3000);

      // least liquid pool
      const pool10000 = await IUniswapV3Factory__factory.connect(
        UNISWAP_V3_FACTORY,
        deployer,
      ).getPool(tokens.WBTC.address, tokens.USDT.address, 10000);

      await instance.upsertPair(tokens.WBTC.address, tokens.USDT.address, {
        gasLimit: 1000000,
      });

      expect(
        await instance.poolsForPair(tokens.WBTC.address, tokens.USDT.address),
      ).to.be.deep.eq([pool3000]);

      await instance.upsertPair(tokens.WBTC.address, tokens.USDT.address, {
        gasLimit: 1500000,
      });

      expect(
        await instance.poolsForPair(tokens.WBTC.address, tokens.USDT.address),
      ).to.be.deep.eq([pool3000, pool500]);

      await instance.setCardinalityPerMinute(1);
      await instance.setPeriod(1);
      await instance.upsertPair(tokens.WBTC.address, tokens.USDT.address);

      expect(
        await instance.poolsForPair(tokens.WBTC.address, tokens.USDT.address),
      ).to.be.deep.eq([pool3000, pool500, pool10000]);
    });
  });

  describe('#quote', async () => {
    it('should revert if pair is not supported', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.quote(tokens.WETH.address, bnToAddress(BigNumber.from(0))),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairNotSupported',
      );
    });

    it('should revert if observation cardinality must be increased', async () => {
      const { instance } = await loadFixture(deploy);

      await instance.setCardinalityPerMinute(20);

      await expect(
        instance.quote(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__ObservationCardinalityTooLow',
      );
    });

    it('should find path if pair has not been added', async () => {
      const { deployer, instance } = await loadFixture(deploy);

      // must increase cardinality to 41 for pool
      await IUniswapV3Pool__factory.connect(
        '0xd8dec118e1215f02e10db846dcbbfe27d477ac19',
        deployer,
      ).increaseObservationCardinalityNext(41);

      expect(await instance.quote(tokens.WETH.address, tokens.DAI.address));
    });

    it('should return quote using correct denomination', async () => {
      const { instance } = await loadFixture(deploy);

      let tokenIn = tokens.WETH; // 18 decimals
      let tokenOut = tokens.DAI; // 18 decimals

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      let quote = await instance.quote(tokenIn.address, tokenOut.address);

      let invertedQuote = await instance.quote(
        tokenOut.address,
        tokenIn.address,
      );

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));

      tokenIn = tokens.WETH; // 18 decimals
      tokenOut = tokens.USDT; // 6 decimals

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      quote = await instance.quote(tokenIn.address, tokenOut.address);
      invertedQuote = await instance.quote(tokenOut.address, tokenIn.address);

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));

      tokenIn = tokens.WBTC; // 8 decimals
      tokenOut = tokens.USDC; // 6 decimals

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      quote = await instance.quote(tokenIn.address, tokenOut.address);
      invertedQuote = await instance.quote(tokenOut.address, tokenIn.address);

      // quote is off by one after dividing by 1E18
      expect(quote.div(ONE_ETHER).add(1)).to.be.eq(
        ONE_ETHER.div(invertedQuote),
      );
    });
  });

  describe('#poolsForPair', () => {
    it('should return pools for pair', async () => {
      const { instance } = await loadFixture(deploy);

      let pools = await instance.poolsForPair(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(pools.length).to.be.eq(0);

      await instance.upsertPair(tokens.WETH.address, tokens.DAI.address);

      pools = await instance.poolsForPair(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(pools).to.be.deep.eq([
        '0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8',
        '0x60594a405d53811d3BC4766596EFD80fd545A270',
        '0xa80964C5bBd1A0E95777094420555fead1A26c1e',
        '0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19',
      ]);
    });
  });

  describe('#factory', () => {
    it('should return correct UniswapV3 factory address', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.factory()).to.be.eq(UNISWAP_V3_FACTORY);
    });
  });

  describe('#period', () =>
    it('should return correct period', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.period()).to.be.eq(period);
    }));

  describe('#cardinalityPerMinute', () => {
    it('should return correct cardinality per minute', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.cardinalityPerMinute()).to.be.eq(
        cardinalityPerMinute,
      );
    });
  });

  describe('#gasPerCardinality', () => {
    it('should return correct gas per cardinality', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.gasPerCardinality()).to.be.eq(22250);
    });
  });

  describe('#gasToSupportPool', () => {
    it('should return correct gas cost to add support for a new pool', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.gasToSupportPool()).to.be.eq(30000);
    });
  });

  describe('#supportedFeeTiers', () => {
    it('should return supported fee tiers', async () => {
      const { instance } = await loadFixture(deploy);
      const feeTiers = await instance.supportedFeeTiers();
      expect(feeTiers).to.be.deep.eq([100, 500, 3000, 10000]);
    });
  });

  describe('#setPeriod', () => {
    const newPeriod = 800;

    it('should revert if not called by owner', async () => {
      const { instance, notOwner } = await loadFixture(deploy);
      await expect(
        instance.connect(notOwner).setPeriod(newPeriod),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should set period to new value', async () => {
      const { instance } = await loadFixture(deploy);
      await instance.setPeriod(newPeriod);
      expect(await instance.period()).to.be.eq(newPeriod);
    });
  });

  describe('#setCardinalityPerMinute', () => {
    const newCardinalityPerMinute = 8;

    it('should revert if not called by owner', async () => {
      const { instance, notOwner } = await loadFixture(deploy);

      await expect(
        instance
          .connect(notOwner)
          .setCardinalityPerMinute(newCardinalityPerMinute),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should revert if cardinality per minute is invalid', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.setCardinalityPerMinute(0),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__InvalidCardinalityPerMinute',
      );
    });

    it('should set cardinality per minute to new value', async () => {
      const { instance } = await loadFixture(deploy);
      await instance.setCardinalityPerMinute(newCardinalityPerMinute);
      expect(await instance.cardinalityPerMinute()).to.be.eq(
        newCardinalityPerMinute,
      );
    });
  });

  describe('#insertFeeTier', () => {
    it('should revert if not called by owner', async () => {
      const { instance, notOwner } = await loadFixture(deploy);
      await expect(
        instance.connect(notOwner).insertFeeTier(200),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should revert if fee tier is invalid', async () => {
      const { instance } = await loadFixture(deploy);
      await expect(instance.insertFeeTier(15000)).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__InvalidFeeTier',
      );
    });

    it('should revert if fee tier exists', async () => {
      const { instance } = await loadFixture(deploy);
      await expect(instance.insertFeeTier(10000)).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__FeeTierExists',
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
