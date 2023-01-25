import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ERC20Mock, ERC20Mock__factory, IPool__factory } from '../../typechain';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { now, revertToSnapshotAfterEach } from '../../utils/time';

describe('PoolFactory', () => {
  let deployer: SignerWithAddress;

  let p: PoolUtil;

  let base: ERC20Mock;
  let underlying: ERC20Mock;
  let baseOracle: MockContract;
  let underlyingOracle: MockContract;

  let isCall = true;
  let strike = parseEther('1000'); // ATM
  let maturity = 1645776000; // Fri Feb 25 2022 08:00:00 GMT+0000
  let blockTimestamp: number;

  before(async () => {
    [deployer] = await ethers.getSigners();

    underlying = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    base = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    p = await PoolUtil.deploy(deployer, underlying.address, true, true);

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(parseUnits('1', 8));
    await baseOracle.mock.decimals.returns(8);

    underlyingOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await underlyingOracle.mock.latestAnswer.returns(parseUnits('1000', 8));
    await underlyingOracle.mock.decimals.returns(8);

    blockTimestamp = await now(); // Tue Dec 28 2021 15:17:14 GMT+0000
  });

  revertToSnapshotAfterEach(async () => {});

  describe('#isPoolDeployed', () => {
    it('should return false if no pool has been deployed with given parameters', async () => {
      expect(
        await p.poolFactory.isPoolDeployed(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.false;
    });

    it('should return true if a pool with given parameters has been deployed', async () => {
      await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        isCall,
      );

      expect(
        await p.poolFactory.isPoolDeployed(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.true;
    });
  });

  describe('#deployPool', () => {
    it('should properly deploy the pool', async () => {
      const tx = await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        isCall,
      );

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      const pool = IPool__factory.connect(poolAddress, deployer);
      const poolSettings = await pool.getPoolSettings();

      expect([
        poolSettings.base,
        poolSettings.underlying,
        poolSettings.baseOracle,
        poolSettings.underlyingOracle,
        poolSettings.strike,
        poolSettings.maturity,
        poolSettings.isCallPool,
      ]).to.deep.eq([
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        isCall,
      ]);
    });

    it('should revert if base and underlying are identical', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          base.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__IdenticalAddresses',
      );
    });

    it('should revert if baseOracle and underlyingOracle are identical', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          baseOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__IdenticalAddresses',
      );
    });

    it('should revert if base, underlying, baseOracle, or underlyingOracle are zero address', async () => {
      await expect(
        p.poolFactory.deployPool(
          ethers.constants.AddressZero,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__ZeroAddress',
      );

      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          ethers.constants.AddressZero,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__ZeroAddress',
      );

      await expect(
        p.poolFactory.deployPool(
          base.address,
          ethers.constants.AddressZero,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__ZeroAddress',
      );

      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          ethers.constants.AddressZero,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__ZeroAddress',
      );
    });

    it('should revert if pool has already been deployed', async () => {
      await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        isCall,
      );

      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__PoolAlreadyDeployed',
      );
    });

    it('should revert if strike is zero', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          0,
          maturity,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionStrikeEqualsZero',
      );
    });

    it('should revert if strike price is not within strike interval', async () => {
      // strike interval: 100
      for (let strike of [
        parseEther('99990'),
        parseEther('1050'),
        parseEther('950'),
        parseEther('11'),
      ]) {
        await expect(
          p.poolFactory.deployPool(
            base.address,
            underlying.address,
            baseOracle.address,
            underlyingOracle.address,
            strike,
            maturity,
            isCall,
          ),
        ).to.be.revertedWithCustomError(
          p.poolFactory,
          'PoolFactory__OptionStrikeInvalid',
        );
      }
    });

    it('should revert if daily option maturity has expired', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          blockTimestamp,
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionExpired',
      );
    });

    it('should revert if daily option maturity is not at 8AM UTC', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1640764801, // Wed Dec 29 2021 08:00:01 GMT+0000
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityNot8UTC',
      );
    });

    it('should revert if weekly option maturity not on Friday', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1641110400, // Sun Jan 02 2022 08:00:00 GMT+0000
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityNotFriday',
      );
    });

    it('should revert if monthly option maturity not on last Friday', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1645171200, // Fri Feb 18 2022 08:00:00 GMT+0000
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityNotLastFriday',
      );
    });

    it('should revert if monthly option maturity exceeds 365 days', async () => {
      await expect(
        p.poolFactory.deployPool(
          base.address,
          underlying.address,
          baseOracle.address,
          underlyingOracle.address,
          strike,
          1672387200, // Fri Dec 30 2022 08:00:00 GMT+0000
          isCall,
        ),
      ).to.be.revertedWithCustomError(
        p.poolFactory,
        'PoolFactory__OptionMaturityExceedsMax',
      );
    });
  });
});
