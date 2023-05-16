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

  describe('#constructor', () => {
    it('should revert if period is zero', async () => {
      const [deployer] = await ethers.getSigners();

      const implementation = await new UniswapV3Adapter__factory(
        deployer,
      ).deploy(UNISWAP_V3_FACTORY, tokens.WETH.address, 22250, 30000);

      await implementation.deployed();

      await expect(
        new UniswapV3AdapterProxy__factory(deployer).deploy(
          0,
          cardinalityPerMinute,
          implementation.address,
        ),
      ).to.be.revertedWithCustomError(
        new UniswapV3AdapterProxy__factory(),
        'UniswapV3AdapterProxy__PeriodNotSet',
      );
    });

    it('should set state variables', async () => {
      const { instance } = await loadFixture(deploy);

      expect(await instance.getTargetCardinality()).to.equal(
        (period * cardinalityPerMinute) / 60 + 1,
      );

      expect(await instance.getPeriod()).to.equal(period);

      expect(await instance.getCardinalityPerMinute()).to.equal(
        cardinalityPerMinute,
      );

      expect(await instance.getSupportedFeeTiers()).to.be.deep.eq([
        100, 500, 3000, 10000,
      ]);
    });
  });

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

    it('should revert if pair has not been added and observation cardinality must be increased', async () => {
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

    it('should skip uninitialized pools and provide quote when no pools are cached', async () => {
      const { deployer, instance } = await loadFixture(deploy);

      let tokenIn = tokens.WETH; // 18 decimals
      let tokenOut = tokens.MKR; // 18 decimals

      await IUniswapV3Pool__factory.connect(
        '0x886072A44BDd944495eFF38AcE8cE75C1EacDAF6',
        deployer,
      ).increaseObservationCardinalityNext(41);

      await IUniswapV3Pool__factory.connect(
        '0x3aFdC5e6DfC0B0a507A8e023c9Dce2CAfC310316',
        deployer,
      ).increaseObservationCardinalityNext(41);

      await IUniswapV3Factory__factory.connect(
        UNISWAP_V3_FACTORY,
        deployer,
      ).createPool(tokenIn.address, tokenOut.address, 100);

      expect(await instance.quote(tokenIn.address, tokenOut.address));
    });

    it('should skip uninitialized pools and provide quote when pools are cached', async () => {
      const { deployer, instance } = await loadFixture(deploy);

      let tokenIn = tokens.WETH; // 18 decimals
      let tokenOut = tokens.MKR; // 18 decimals

      await instance.upsertPair(tokenIn.address, tokenOut.address);
      expect(await instance.quote(tokenIn.address, tokenOut.address));

      await IUniswapV3Factory__factory.connect(
        UNISWAP_V3_FACTORY,
        deployer,
      ).createPool(tokenIn.address, tokenOut.address, 100);

      expect(await instance.quote(tokenIn.address, tokenOut.address));

      await IUniswapV3Pool__factory.connect(
        '0xd9d92C02a8fd1DdB731381f1351DACA19928E0db',
        deployer,
      ).initialize(4295128740);

      await expect(
        instance.quote(tokenIn.address, tokenOut.address),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__ObservationCardinalityTooLow',
      );

      await IUniswapV3Pool__factory.connect(
        '0xd9d92C02a8fd1DdB731381f1351DACA19928E0db',
        deployer,
      ).increaseObservationCardinalityNext(41);

      await increase(600);

      expect(await instance.quote(tokenIn.address, tokenOut.address));
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
        '0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19',
        '0x60594a405d53811d3BC4766596EFD80fd545A270',
        '0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8',
        '0xa80964C5bBd1A0E95777094420555fead1A26c1e',
      ]);
    });
  });

  describe('#getFactory', () => {
    it('should return correct UniswapV3 factory address', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.getFactory()).to.be.eq(UNISWAP_V3_FACTORY);
    });
  });

  describe('#getPeriod', () =>
    it('should return correct period', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.getPeriod()).to.be.eq(period);
    }));

  describe('#getCardinalityPerMinute', () => {
    it('should return correct cardinality per minute', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.getCardinalityPerMinute()).to.be.eq(
        cardinalityPerMinute,
      );
    });
  });

  describe('#getGasPerCardinality', () => {
    it('should return correct gas per cardinality', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.getGasPerCardinality()).to.be.eq(22250);
    });
  });

  describe('#getGasToSupportPool', () => {
    it('should return correct gas cost to add support for a new pool', async () => {
      const { instance } = await loadFixture(deploy);
      expect(await instance.getGasToSupportPool()).to.be.eq(30000);
    });
  });

  describe('#getSupportedFeeTiers', () => {
    it('should return supported fee tiers', async () => {
      const { instance } = await loadFixture(deploy);
      const feeTiers = await instance.getSupportedFeeTiers();
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

    it('should revert if period is not set', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(instance.setPeriod(0)).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__PeriodNotSet',
      );
    });

    it('should set period to new value', async () => {
      const { instance } = await loadFixture(deploy);
      await instance.setPeriod(newPeriod);
      expect(await instance.getPeriod()).to.be.eq(newPeriod);
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

    it('should revert if cardinality per minute is not set', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.setCardinalityPerMinute(0),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__CardinalityPerMinuteNotSet',
      );
    });

    it('should set cardinality per minute to new value', async () => {
      const { instance } = await loadFixture(deploy);
      await instance.setCardinalityPerMinute(newCardinalityPerMinute);
      expect(await instance.getCardinalityPerMinute()).to.be.eq(
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

  describe('#describePricingPath', () => {
    it('should describe pricing path', async () => {
      const { instance } = await loadFixture(deploy);

      let description = await instance.describePricingPath(
        bnToAddress(BigNumber.from(1)),
      );

      expect(description.adapterType).to.eq(AdapterType.UNISWAP_V3);
      expect(description.path.length).to.eq(0);
      expect(description.decimals.length).to.eq(0);

      description = await instance.describePricingPath(tokens.WETH.address);

      expect(description.adapterType).to.eq(AdapterType.UNISWAP_V3);
      expect(description.path).to.deep.eq([
        ['0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'],
      ]);
      expect(description.decimals).to.deep.eq([18]);

      description = await instance.describePricingPath(tokens.DAI.address);

      expect(description.adapterType).to.eq(AdapterType.UNISWAP_V3);
      expect(description.path).to.deep.eq([
        [
          '0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19',
          '0x60594a405d53811d3BC4766596EFD80fd545A270',
          '0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8',
          '0xa80964C5bBd1A0E95777094420555fead1A26c1e',
        ],
      ]);
      expect(description.decimals).to.deep.eq([18, 18]);

      description = await instance.describePricingPath(tokens.USDC.address);

      expect(description.adapterType).to.eq(AdapterType.UNISWAP_V3);
      expect(description.path).to.deep.eq([
        [
          '0xE0554a476A092703abdB3Ef35c80e0D76d32939F',
          '0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640',
          '0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8',
          '0x7BeA39867e4169DBe237d55C8242a8f2fcDcc387',
        ],
      ]);
      expect(description.decimals).to.deep.eq([6, 18]);
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
