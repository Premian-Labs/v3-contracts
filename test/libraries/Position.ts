import { expect } from 'chai';
import { ethers } from 'hardhat';
import { PositionMock__factory } from '../../typechain';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { average } from '../../utils/sdk/math';
import { OrderType } from '../../utils/sdk/types';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

describe('Position', () => {
  const strike = parseEther('1000');
  const isCall = true;
  const WAD = parseEther('1');

  async function deploy() {
    const [deployer] = await ethers.getSigners();
    const instance = await new PositionMock__factory(deployer).deploy();

    const key = {
      owner: deployer.address,
      operator: deployer.address,
      lower: parseEther('0.25'),
      upper: parseEther('0.75'),
      orderType: 0,
      isCall: isCall,
      strike: strike,
    };

    return { deployer, instance, key };
  }

  describe('#keyHash', () => {
    it('should return key hash', async () => {
      const { key, instance } = await loadFixture(deploy);

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
      const { instance } = await loadFixture(deploy);

      expect(await instance.isShort(OrderType.CS)).is.true;
      expect(await instance.isShort(OrderType.CSUP)).is.true;
    });

    it('should return false if orderType is not short', async () => {
      const { instance } = await loadFixture(deploy);

      expect(await instance.isShort(OrderType.LC)).is.false;
    });
  });

  describe('#isLong', () => {
    it('should return true if orderType is long', async () => {
      const { instance } = await loadFixture(deploy);

      expect(await instance.isLong(OrderType.LC)).is.true;
    });

    it('should return true if orderType is not long', async () => {
      const { instance } = await loadFixture(deploy);

      expect(await instance.isLong(OrderType.CS)).is.false;
      expect(await instance.isLong(OrderType.CSUP)).is.false;
    });
  });

  describe('#pieceWiseLinear', () => {
    it('should return 0 if lower >= price', async () => {
      const { instance, key } = await loadFixture(deploy);

      expect(await instance.pieceWiseLinear(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseLinear(key, key.lower.sub(1))).to.eq(0);
    });

    for (const c of [
      ['0.3', '0.1'],
      ['0.5', '0.5'],
      ['0.7', '0.9'],
    ]) {
      it(`should return ${c[1]} for price ${c[0]} if lower < price && price < upper`, async () => {
        const { instance, key } = await loadFixture(deploy);

        expect(await instance.pieceWiseLinear(key, parseEther(c[0]))).to.eq(
          parseEther(c[1]),
        );
      });
    }

    it('should return WAD if price > upper', async () => {
      const { instance, key } = await loadFixture(deploy);

      expect(await instance.pieceWiseLinear(key, key.upper)).to.eq(WAD);
      expect(await instance.pieceWiseLinear(key, key.upper.add(1))).to.eq(WAD);
    });

    it('should revert if lower >= upper', async () => {
      const { instance, key } = await loadFixture(deploy);

      const newKey = { ...key, lower: key.upper };

      await expect(
        instance.pieceWiseLinear(newKey, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      newKey.lower = newKey.upper.add(1);

      await expect(
        instance.pieceWiseLinear(newKey, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });

  describe('#pieceWiseQuadratic', async () => {
    it('should return 0 if lower >= price', async () => {
      const { instance, key } = await loadFixture(deploy);

      expect(await instance.pieceWiseQuadratic(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseQuadratic(key, key.lower.sub(1))).to.eq(0);
    });

    for (let c of [
      ['0.3', '0.0275'],
      ['0.5', '0.1875'],
      ['0.7', '0.4275'],
    ]) {
      it(`should return ${c[1]} for price ${c[0]} if lower < price && price < upper`, async () => {
        const { instance, key } = await loadFixture(deploy);

        expect(await instance.pieceWiseQuadratic(key, parseEther(c[0]))).to.eq(
          parseEther(c[1]),
        );
      });
    }

    it('should return average price if price >= upper', async () => {
      const { instance, key } = await loadFixture(deploy);

      expect(await instance.pieceWiseQuadratic(key, key.upper)).to.eq(
        average(key.lower, key.upper),
      );

      expect(await instance.pieceWiseQuadratic(key, key.upper.add(1))).to.eq(
        average(key.lower, key.upper),
      );
    });

    it('should revert if lower >= upper', async () => {
      const { instance, key } = await loadFixture(deploy);

      const newKey = { ...key, lower: key.upper };

      await expect(
        instance.pieceWiseQuadratic(newKey, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      newKey.lower = newKey.upper.add(1);

      await expect(
        instance.pieceWiseQuadratic(newKey, 0),
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
          const { instance } = await loadFixture(deploy);

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
          const { instance } = await loadFixture(deploy);

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
          const { instance } = await loadFixture(deploy);

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
          const { instance } = await loadFixture(deploy);

          expect(
            await instance.contractsToCollateral(contracts, strike, !isCall),
          ).to.eq(collateral);
        });
      }
    });
  });

  describe('#liquidityPerTick', () => {
    for (let c of [
      ['0.25', '0.75', '250', '0.5'],
      ['0.25', '0.75', '500', '1'],
      ['0.25', '0.75', '1000', '2'],
    ]) {
      it(`should return ${c[3]} for size ${c[2]} and range ${c[0]} - ${c[1]}`, async () => {
        const { instance, key } = await loadFixture(deploy);

        const newKey = {
          ...key,
          lower: parseEther(c[0]),
          upper: parseEther(c[1]),
        };

        expect(await instance.liquidityPerTick(newKey, parseEther(c[2]))).to.eq(
          parseEther(c[3]),
        );
      });
    }
  });

  describe('#bid', () => {
    const cases = [
      ['0.5', '0.3', '0.01375'],
      ['1', '0.5', '0.1875'],
      ['2', '0.7', '0.855'],
    ];

    describe('#call options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[2]);

        it(`should return ${c[2]} unit(s) of collateral for size ${c[0]} and price ${c[1]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          expect(
            await instance.bid(key, parseEther(c[0]), parseEther(c[1])),
          ).to.eq(collateral);
        });
      }
    });

    describe('#put options', () => {
      for (let c of cases) {
        let collateral = parseEther(c[2]).mul(strike).div(parseEther('1'));
        let formattedCollateral = formatEther(collateral);

        it(`should return ${formattedCollateral} unit(s) of collateral for size ${c[0]} and price ${c[1]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          expect(
            await instance.bid(
              { ...key, isCall: !key.isCall },
              parseEther(c[0]),
              parseEther(c[1]),
            ),
          ).to.eq(collateral);
        });
      }
    });
  });

  describe('#collateral', () => {
    const size = '2';

    describe('OrderType CSUP', () => {
      const cases = [
        ['0.2', '1.'],
        ['0.25', '1.'],
        ['0.3', '0.855'],
        ['0.5', '0.375'],
        ['0.7', '0.055'],
        ['0.75', '0'],
        ['0.8', '0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for size ${size}, and price ${c[0]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let collateral = await instance.collateral(
            { ...key, orderType: OrderType.CSUP },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(collateral).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType CS', () => {
      const cases = [
        ['0.2', '2.'],
        ['0.25', '2.'],
        ['0.3', '1.855'],
        ['0.5', '1.375'],
        ['0.7', '1.055'],
        ['0.75', '1.0'],
        ['0.8', '1.0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for size ${size}, and price ${c[0]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let collateral = await instance.collateral(
            { ...key, orderType: OrderType.CS },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(collateral).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType LC', () => {
      const cases = [
        ['0.2', '0'],
        ['0.25', '0'],
        ['0.3', '0.055'],
        ['0.5', '0.375'],
        ['0.7', '0.855'],
        ['0.75', '1.0'],
        ['0.8', '1.0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for size ${size}, and price ${c[0]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let collateral = await instance.collateral(
            { ...key, orderType: OrderType.LC },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(collateral).to.eq(parseEther(c[1]));
        });
      }
    });
  });

  describe('#contracts', () => {
    const size = '2';

    describe('OrderType CSUP', () => {
      const cases = [
        ['0.2', '0'],
        ['0.25', '0'],
        ['0.3', '0.2'],
        ['0.5', '1.0'],
        ['0.7', '1.8'],
        ['0.75', '2.0'],
        ['0.8', '2.0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for size ${size} and price ${c[0]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.contracts(
            { ...key, orderType: OrderType.CSUP },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType CS', () => {
      const cases = [
        ['0.2', '0'],
        ['0.25', '0'],
        ['0.3', '0.2'],
        ['0.5', '1.0'],
        ['0.7', '1.8'],
        ['0.75', '2.0'],
        ['0.8', '2.0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for size ${size} and price ${c[0]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.contracts(
            { ...key, orderType: OrderType.CS },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType LC', () => {
      const cases = [
        ['0.2', '2.'],
        ['0.25', '2.'],
        ['0.3', '1.8'],
        ['0.5', '1.0'],
        ['0.7', '0.2'],
        ['0.75', '0'],
        ['0.8', '0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for size ${size} and price ${c[0]}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.contracts(
            { ...key, orderType: OrderType.LC },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });
  });

  describe('#long', () => {
    const size = '2';

    describe('OrderType CSUP', () => {
      const cases = [
        ['0.2', '0'],
        ['0.25', '0'],
        ['0.3', '0'],
        ['0.5', '0'],
        ['0.7', '0'],
        ['0.75', '0'],
        ['0.8', '0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for price ${c[0]}, and size ${size}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.long(
            { ...key, orderType: OrderType.CSUP },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType CS', () => {
      const cases = [
        ['0.2', '0'],
        ['0.25', '0'],
        ['0.3', '0'],
        ['0.5', '0'],
        ['0.7', '0'],
        ['0.75', '0'],
        ['0.8', '0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for price ${c[0]}, and size ${size}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.long(
            { ...key, orderType: OrderType.CS },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType LC', () => {
      const cases = [
        ['0.2', '2.0'],
        ['0.25', '2.0'],
        ['0.3', '1.8'],
        ['0.5', '1.0'],
        ['0.7', '0.2'],
        ['0.75', '0.0'],
        ['0.8', '0.0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for price ${c[0]}, and size ${size}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.long(
            { ...key, orderType: OrderType.LC },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });
  });

  describe('#short', () => {
    const size = '2';

    describe('OrderType CSUP', () => {
      const cases = [
        ['0.2', '0.0'],
        ['0.25', '0.0'],
        ['0.3', '0.2'],
        ['0.5', '1.0'],
        ['0.7', '1.8'],
        ['0.75', '2.0'],
        ['0.8', '2.0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for price ${c[0]}, and size ${size}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.short(
            { ...key, orderType: OrderType.CSUP },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType CS', () => {
      const cases = [
        ['0.2', '0.0'],
        ['0.25', '0.0'],
        ['0.3', '0.2'],
        ['0.5', '1.0'],
        ['0.7', '1.8'],
        ['0.75', '2.0'],
        ['0.8', '2.0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for price ${c[0]}, and size ${size}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.short(
            { ...key, orderType: OrderType.CS },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });

    describe('OrderType LC', () => {
      const cases = [
        ['0.2', '0'],
        ['0.25', '0'],
        ['0.3', '0'],
        ['0.5', '0'],
        ['0.7', '0'],
        ['0.75', '0'],
        ['0.8', '0'],
      ];

      for (let c of cases) {
        it(`should return ${c[1]} contracts for price ${c[0]}, and size ${size}`, async () => {
          const { instance, key } = await loadFixture(deploy);

          let contracts = await instance.short(
            { ...key, orderType: OrderType.LC },
            parseEther(size),
            parseEther(c[0]),
          );

          expect(contracts).to.eq(parseEther(c[1]));
        });
      }
    });
  });

  describe('#calculatePositionUpdate', () => {
    const prices = ['0.2', '0.25', '0.3', '0.6', '0.75', '0.8'];
    const deltas = ['0.8', '1.2'];
    const actions = [true, false];
    const currentBalance = parseEther('2');

    describe('OrderType CSUP', () => {
      const expected = [
        ['0.400', '0.000', '0.000'],
        ['0.400', '0.000', '0.000'],
        ['0.342', '0.000', '0.080'],
        ['0.078', '0.000', '0.560'],
        ['0.000', '0.000', '0.800'],
        ['0.000', '0.000', '0.800'],
        ['0.600', '0.000', '0.000'],
        ['0.600', '0.000', '0.000'],
        ['0.513', '0.000', '0.120'],
        ['0.117', '0.000', '0.840'],
        ['0.000', '0.000', '1.200'],
        ['0.000', '0.000', '1.200'],
        ['-0.400', '-0.000', '-0.000'],
        ['-0.400', '-0.000', '-0.000'],
        ['-0.342', '-0.000', '-0.080'],
        ['-0.078', '-0.000', '-0.560'],
        ['-0.000', '-0.000', '-0.800'],
        ['-0.000', '-0.000', '-0.800'],
        ['-0.600', '-0.000', '-0.000'],
        ['-0.600', '-0.000', '-0.000'],
        ['-0.513', '-0.000', '-0.120'],
        ['-0.117', '-0.000', '-0.840'],
        ['-0.000', '-0.000', '-1.200'],
        ['-0.000', '-0.000', '-1.200'],
      ];

      let counter: number = 0;
      for (let is_deposit of actions) {
        for (let deltaBalance of deltas) {
          for (let price of prices) {
            it(`price ${price}, amount ${deltaBalance}, is_deposit ${is_deposit}`, async () => {
              const { instance, key } = await loadFixture(deploy);

              let sign: number;

              if (is_deposit) {
                sign = 1;
              } else {
                sign = -1;
              }

              let formattedDeltaBalance = parseEther(deltaBalance).mul(sign);
              let formattedPrice = parseEther(price);

              let delta = await instance.calculatePositionUpdate(
                { ...key, orderType: OrderType.CSUP },
                currentBalance,
                formattedDeltaBalance,
                formattedPrice,
              );
              expect(delta.collateral).to.eq(parseEther(expected[counter][0]));
              expect(delta.longs).to.eq(parseEther(expected[counter][1]));
              expect(delta.shorts).to.eq(parseEther(expected[counter][2]));
              counter++;
            });
          }
        }
      }
    });

    describe('OrderType CS', () => {
      const expected = [
        ['0.800', '0.000', '0.000'],
        ['0.800', '0.000', '0.000'],
        ['0.742', '0.000', '0.080'],
        ['0.478', '0.000', '0.560'],
        ['0.400', '0.000', '0.800'],
        ['0.400', '0.000', '0.800'],
        ['1.200', '0.000', '0.000'],
        ['1.200', '0.000', '0.000'],
        ['1.113', '0.000', '0.120'],
        ['0.717', '0.000', '0.840'],
        ['0.600', '0.000', '1.200'],
        ['0.600', '0.000', '1.200'],
        ['-0.800', '-0.000', '-0.000'],
        ['-0.800', '-0.000', '-0.000'],
        ['-0.742', '-0.000', '-0.080'],
        ['-0.478', '-0.000', '-0.560'],
        ['-0.400', '-0.000', '-0.800'],
        ['-0.400', '-0.000', '-0.800'],
        ['-1.200', '-0.000', '-0.000'],
        ['-1.200', '-0.000', '-0.000'],
        ['-1.113', '-0.000', '-0.120'],
        ['-0.717', '-0.000', '-0.840'],
        ['-0.600', '-0.000', '-1.200'],
        ['-0.600', '-0.000', '-1.200'],
      ];

      let counter: number = 0;
      for (let is_deposit of actions) {
        for (let deltaBalance of deltas) {
          for (let price of prices) {
            it(`price ${price}, amount ${deltaBalance}, is_deposit ${is_deposit}`, async () => {
              const { instance, key } = await loadFixture(deploy);

              let sign: number;

              if (is_deposit) {
                sign = 1;
              } else {
                sign = -1;
              }

              let formattedDeltaBalance = parseEther(deltaBalance).mul(sign);
              let formattedPrice = parseEther(price);

              let delta = await instance.calculatePositionUpdate(
                { ...key, orderType: OrderType.CS },
                currentBalance,
                formattedDeltaBalance,
                formattedPrice,
              );
              expect(delta.collateral).to.eq(parseEther(expected[counter][0]));
              expect(delta.longs).to.eq(parseEther(expected[counter][1]));
              expect(delta.shorts).to.eq(parseEther(expected[counter][2]));
              counter++;
            });
          }
        }
      }
    });

    describe('OrderType LC', () => {
      const expected = [
        ['0.000', '0.800', '0.000'],
        ['0.000', '0.800', '0.000'],
        ['0.022', '0.720', '0.000'],
        ['0.238', '0.240', '0.000'],
        ['0.400', '0.000', '0.000'],
        ['0.400', '0.000', '0.000'],
        ['0.000', '1.200', '0.000'],
        ['0.000', '1.200', '0.000'],
        ['0.033', '1.080', '0.000'],
        ['0.357', '0.360', '0.000'],
        ['0.600', '0.000', '0.000'],
        ['0.600', '0.000', '0.000'],
        ['-0.000', '-0.800', '-0.000'],
        ['-0.000', '-0.800', '-0.000'],
        ['-0.022', '-0.720', '-0.000'],
        ['-0.238', '-0.240', '-0.000'],
        ['-0.400', '-0.000', '-0.000'],
        ['-0.400', '-0.000', '-0.000'],
        ['-0.000', '-1.200', '-0.000'],
        ['-0.000', '-1.200', '-0.000'],
        ['-0.033', '-1.080', '-0.000'],
        ['-0.357', '-0.360', '-0.000'],
        ['-0.600', '-0.000', '-0.000'],
        ['-0.600', '-0.000', '-0.000'],
      ];

      let counter: number = 0;
      for (let is_deposit of actions) {
        for (let deltaBalance of deltas) {
          for (let price of prices) {
            it(`price ${price}, amount ${deltaBalance}, is_deposit ${is_deposit}`, async () => {
              const { instance, key } = await loadFixture(deploy);

              let sign: number;

              if (is_deposit) {
                sign = 1;
              } else {
                sign = -1;
              }

              let formattedDeltaBalance = parseEther(deltaBalance).mul(sign);
              let formattedPrice = parseEther(price);

              let delta = await instance.calculatePositionUpdate(
                { ...key, orderType: OrderType.LC },
                currentBalance,
                formattedDeltaBalance,
                formattedPrice,
              );
              expect(delta.collateral).to.eq(parseEther(expected[counter][0]));
              expect(delta.longs).to.eq(parseEther(expected[counter][1]));
              expect(delta.shorts).to.eq(parseEther(expected[counter][2]));
              counter++;
            });
          }
        }
      }
    });
  });
});
