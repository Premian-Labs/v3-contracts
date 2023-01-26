import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PositionMock, PositionMock__factory } from '../../typechain';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { average } from '../../utils/math';

describe('Position', () => {
  let deployer: SignerWithAddress;
  let instance: PositionMock;

  let strike = parseEther('1000');
  let isCall = true;

  let key: any;

  let WAD = parseEther('1');

  enum OrderType {
    CSUP,
    CS,
    LC,
  }

  before(async () => {
    [deployer] = await ethers.getSigners();
    instance = await new PositionMock__factory(deployer).deploy();
  });

  beforeEach(async () => {
    key = {
      owner: deployer.address,
      operator: deployer.address,
      lower: parseEther('0.25'),
      upper: parseEther('0.75'),
      orderType: 0,
      isCall: isCall,
      strike: strike,
    };
  });

  describe('#keyHash', () => {
    it('should return key hash', async () => {
      const keyHash = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256', 'uint256', 'uint8'],
          [key.owner, key.operator, key.lower, key.upper, key.orderType],
        ),
      );

      expect(await instance.keyHash(key)).to.eq(keyHash);
    });
  });

  describe('#isShort', () => {
    it('should return true if orderType is short', async () => {
      expect(await instance.isShort(OrderType.CS)).is.true;
      expect(await instance.isShort(OrderType.CSUP)).is.true;
    });

    it('should return false if orderType is not short', async () => {
      expect(await instance.isShort(OrderType.LC)).is.false;
    });
  });

  describe('#isLong', () => {
    it('should return true if orderType is long', async () => {
      expect(await instance.isLong(OrderType.LC)).is.true;
    });

    it('should return true if orderType is not long', async () => {
      expect(await instance.isLong(OrderType.CS)).is.false;
      expect(await instance.isLong(OrderType.CSUP)).is.false;
    });
  });

  describe('#pieceWiseLinear', () => {
    it('should return 0 if lower >= price', async () => {
      expect(await instance.pieceWiseLinear(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseLinear(key, key.lower.sub(1))).to.eq(0);
    });

    it('should return the price if lower < price && price < upper', async () => {
      for (const t of [
        [parseEther('0.3'), parseEther('0.1')],
        [parseEther('0.5'), parseEther('0.5')],
        [parseEther('0.7'), parseEther('0.9')],
      ]) {
        expect(await instance.pieceWiseLinear(key, t[0])).to.eq(t[1]);
      }
    });

    it('should return WAD if price > upper', async () => {
      expect(await instance.pieceWiseLinear(key, key.upper)).to.eq(WAD);
      expect(await instance.pieceWiseLinear(key, key.upper.add(1))).to.eq(WAD);
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        instance.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        instance.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });

  describe('#pieceWiseQuadratic', async () => {
    it('should return 0 if lower >= price', async () => {
      expect(await instance.pieceWiseQuadratic(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseQuadratic(key, key.lower.sub(1))).to.eq(0);
    });

    it('should return the price if lower < price && price < upper', async () => {
      for (const t of [
        [parseEther('0.3'), parseEther('0.0275')],
        [parseEther('0.5'), parseEther('0.1875')],
        [parseEther('0.7'), parseEther('0.4275')],
      ]) {
        expect(await instance.pieceWiseQuadratic(key, t[0])).to.eq(t[1]);
      }
    });

    it('should return average price if price > upper', async () => {
      expect(await instance.pieceWiseQuadratic(key, key.upper)).to.eq(
        average(key.lower, key.upper),
      );

      expect(await instance.pieceWiseQuadratic(key, key.upper.add(1))).to.eq(
        average(key.lower, key.upper),
      );
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        instance.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        instance.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });

  describe('#collateralToContracts', () => {
    const cases = [
      ['1', '0.001'],
      ['77', '0.77'],
      ['344', '0.344'],
      ['5235', '5.235'],
      ['99999', '99.999'],
    ];

    describe('#call options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[0]);
        let contracts = collateral;

        it(`should return ${c[0]} contract(s) for ${c[0]} uint(s) of collateral`, async () => {
          expect(
            await instance.collateralToContracts(collateral, strike, isCall),
          ).to.eq(contracts);
        });
      }
    });

    describe('#put options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[0]);
        let contracts = collateral.mul(parseEther('1')).div(strike);
        let formattedContracts = formatEther(contracts);

        it(`should return ${formattedContracts} contract(s) for ${c[0]} uint(s) of collateral`, async () => {
          expect(
            await instance.collateralToContracts(collateral, strike, !isCall),
          ).to.eq(contracts);
        });
      }
    });
  });

  describe('#contractsToCollateral', () => {
    const cases = [
      ['1', '0.001'],
      ['77', '0.77'],
      ['344', '0.344'],
      ['5235', '5.235'],
      ['99999', '99.999'],
    ];

    describe('#call options', () => {
      for (let c of cases) {
        let contracts = parseEther(c[0]);
        let collateral = contracts;

        it(`should return ${c[0]} unit(s) of collateral for ${c[0]} contract(s)`, async () => {
          expect(
            await instance.contractsToCollateral(contracts, strike, isCall),
          ).to.eq(collateral);
        });
      }
    });

    describe('#put options', () => {
      for (let c of cases) {
        let contracts = parseEther(c[0]);
        let collateral = contracts.mul(strike).div(parseEther('1'));
        let formattedCollateral = formatEther(collateral);

        it(`should return ${formattedCollateral} unit(s) of collateral for ${c[0]} contract(s)`, async () => {
          expect(
            await instance.contractsToCollateral(contracts, strike, !isCall),
          ).to.eq(collateral);
        });
      }
    });
  });
          ).to.eq(collateral);
        });
      }
    });

    describe('#put options', () => {
      for (let c of amounts) {
        let collateral = parseEther(c[0]);
        let contracts = collateral.mul(strike).div(parseEther('1'));

        it(`should return ${c[0]} unit(s) of collateral for ${c[1]} contract(s)`, async () => {
          expect(
            await instance.contractsToCollateral(collateral, strike, !isCall),
          ).to.eq(contracts);
        });
      }
    });
  });
});
