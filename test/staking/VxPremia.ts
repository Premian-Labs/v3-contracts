import {
  ERC20Mock__factory,
  VxPremia,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../../typechain';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { parseEther, solidityPack } from 'ethers/lib/utils';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { increase, ONE_DAY } from '../../utils/time';
import { getEventArgs } from '../../utils/events';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

/* Example to decode packed target data

const targetData = '0x000000000000000000000000000000000000000101;
const pool = hexDataSlice(
  targetData,
  0,
  20,
);
const isCallPool = hexDataSlice(
  targetData,
  20,
  21,
);

 */

////////////////////

const poolAddresses = [
  '0x000004354F938CF1aCC2414B68951ad7a8730fB6',
  '0x100004354F938CF1aCC2414B68951ad7a8730fB6',
  '0x200004354F938CF1aCC2414B68951ad7a8730fB6',
];

describe('VxPremia', () => {
  async function deploy() {
    const [deployer, alice, bob] = await ethers.getSigners();

    const premia = await new ERC20Mock__factory(deployer).deploy('PREMIA', 18);
    const usdc = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    const premiaDiamond = await deployMockContract(deployer as any, [
      'function getPoolList() external view returns (uint256[])',
    ]);

    await premiaDiamond.mock.getPoolList.returns(poolAddresses);

    const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
      premiaDiamond.address,
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
      ethers.constants.AddressZero,
    );

    const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
      vxPremiaImpl.address,
    );

    const vxPremia = VxPremia__factory.connect(vxPremiaProxy.address, deployer);

    for (const u of [alice, bob]) {
      await premia.mint(u.address, parseEther('100'));
      await premia
        .connect(u)
        .approve(vxPremia.address, ethers.constants.MaxUint256);
    }

    return { deployer, alice, bob, premia, usdc, vxPremia, poolAddresses };
  }

  describe('#getUserVotes', () => {
    it('should successfully return user votes', async () => {
      const { vxPremia, alice } = await loadFixture(deploy);

      await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

      const votes = [
        {
          amount: parseEther('1'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[0], true]),
        },
        {
          amount: parseEther('10'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[1], true]),
        },
        {
          amount: parseEther('1.5'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[1], false]),
        },
      ];

      await vxPremia.connect(alice).castVotes(votes);

      expect(
        (await vxPremia.getUserVotes(alice.address)).map((el) => {
          return {
            amount: el.amount,
            version: el.version,
            target: el.target,
          };
        }),
      ).to.deep.eq(votes);
    });
  });

  describe('#castVotes', () => {
    it('should fail casting user vote if not enough voting power', async () => {
      const { vxPremia, alice } = await loadFixture(deploy);

      await expect(
        vxPremia.connect(alice).castVotes([
          {
            amount: parseEther('1'),
            version: 0,
            target: solidityPack(['address', 'bool'], [poolAddresses[0], true]),
          },
        ]),
      ).to.be.revertedWithCustomError(
        vxPremia,
        'VxPremia__NotEnoughVotingPower',
      );

      await vxPremia.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      await expect(
        vxPremia.connect(alice).castVotes([
          {
            amount: parseEther('10'),
            version: 0,
            target: solidityPack(['address', 'bool'], [poolAddresses[0], true]),
          },
        ]),
      ).to.be.revertedWithCustomError(
        vxPremia,
        'VxPremia__NotEnoughVotingPower',
      );
    });

    it('should successfully cast user votes', async () => {
      const { vxPremia, alice } = await loadFixture(deploy);

      await vxPremia.connect(alice).stake(parseEther('5'), ONE_DAY * 365);

      await vxPremia.connect(alice).castVotes([
        {
          amount: parseEther('1'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[0], true]),
        },
        {
          amount: parseEther('3'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[1], true]),
        },
        {
          amount: parseEther('2.25'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[1], false]),
        },
      ]);

      let votes = await vxPremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[0], true]),
        ],
        [
          parseEther('3'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[1], true]),
        ],
        [
          parseEther('2.25'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[1], false]),
        ],
      ]);

      // Casting new votes should remove all existing votes, and set new ones

      await vxPremia.connect(alice).castVotes([
        {
          amount: parseEther('2'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[0], false]),
        },
      ]);

      votes = await vxPremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('2'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[0], false]),
        ],
      ]);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [poolAddresses[0], true]),
        ),
      ).to.eq(0);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [poolAddresses[1], true]),
        ),
      ).to.eq(0);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [poolAddresses[1], false]),
        ),
      ).to.eq(0);

      expect(
        await vxPremia.getPoolVotes(
          0,
          solidityPack(['address', 'bool'], [poolAddresses[0], false]),
        ),
      ).to.eq(parseEther('2'));
    });

    it('should remove some user votes if some tokens are withdrawn', async () => {
      const { vxPremia, alice } = await loadFixture(deploy);

      await vxPremia.connect(alice).stake(parseEther('5'), ONE_DAY * 365);

      await vxPremia.connect(alice).castVotes([
        {
          amount: parseEther('1'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[0], true]),
        },
        {
          amount: parseEther('3'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[1], true]),
        },
        {
          amount: parseEther('2.25'),
          version: 0,
          target: solidityPack(['address', 'bool'], [poolAddresses[1], false]),
        },
      ]);

      await increase(ONE_DAY * 366);

      let votes = await vxPremia.getUserVotes(alice.address);
      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[0], true]),
        ],
        [
          parseEther('3'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[1], true]),
        ],
        [
          parseEther('2.25'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[1], false]),
        ],
      ]);

      expect(await vxPremia.getUserPower(alice.address)).to.eq(
        parseEther('6.25'),
      );

      await vxPremia.connect(alice).startWithdraw(parseEther('2.5'));

      votes = await vxPremia.getUserVotes(alice.address);

      expect(votes).to.deep.eq([
        [
          parseEther('1'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[0], true]),
        ],
        [
          parseEther('2.125'),
          0,
          solidityPack(['address', 'bool'], [poolAddresses[1], true]),
        ],
      ]);

      expect(await vxPremia.getUserPower(alice.address)).to.eq(
        parseEther('3.125'),
      );
    });
  });

  it('should successfully update total pool votes', async () => {
    const { vxPremia, alice } = await loadFixture(deploy);

    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('12.5'),
        version: 0,
        target: solidityPack(['address', 'bool'], [poolAddresses[0], true]),
      },
    ]);

    await increase(ONE_DAY * 366);

    const target = solidityPack(['address', 'bool'], [poolAddresses[0], true]);
    expect(await vxPremia.getPoolVotes(0, target)).to.eq(parseEther('12.5'));

    await vxPremia.connect(alice).startWithdraw(parseEther('5'));

    expect(await vxPremia.getPoolVotes(0, target)).to.eq(parseEther('6.25'));
  });

  it('should properly remove all votes if unstaking all', async () => {
    const { vxPremia, alice } = await loadFixture(deploy);

    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('6.25'),
        version: 0,
        target: solidityPack(['address', 'bool'], [poolAddresses[0], true]),
      },
      {
        amount: parseEther('6.25'),
        version: 0,
        target: solidityPack(['address', 'bool'], [poolAddresses[1], true]),
      },
    ]);

    await increase(ONE_DAY * 366);

    expect((await vxPremia.getUserVotes(alice.address)).length).to.eq(2);

    await vxPremia.connect(alice).startWithdraw(parseEther('10'));

    expect((await vxPremia.getUserVotes(alice.address)).length).to.eq(0);
  });

  it('should emit RemoveVote event', async () => {
    const { vxPremia, alice } = await loadFixture(deploy);

    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    const target1 = solidityPack(['address', 'bool'], [poolAddresses[0], true]);

    const target2 = solidityPack(['address', 'bool'], [poolAddresses[1], true]);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    await increase(ONE_DAY * 366);

    let tx = await vxPremia.connect(alice).startWithdraw(parseEther('4'));
    let event = await getEventArgs(tx, 'RemoveVote');

    expect(event[0].voter).to.eq(alice.address);
    expect(event[0].version).to.eq(0);
    expect(event[0].target).to.eq(target2);
    expect(event[0].amount).to.eq(parseEther('2.5'));

    tx = await vxPremia.connect(alice).startWithdraw(parseEther('4'));
    event = await getEventArgs(tx, 'RemoveVote');

    expect(event[0].voter).to.eq(alice.address);
    expect(event[0].version).to.eq(0);
    expect(event[0].target).to.eq(target2);
    expect(event[0].amount).to.eq(parseEther('0.5'));

    expect(event[1].voter).to.eq(alice.address);
    expect(event[1].version).to.eq(0);
    expect(event[1].target).to.eq(target1);
    expect(event[1].amount).to.eq(parseEther('4.5'));
  });

  it('should reset user votes', async () => {
    const { vxPremia, alice, deployer } = await loadFixture(deploy);

    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    const target1 = solidityPack(['address', 'bool'], [poolAddresses[0], true]);

    const target2 = solidityPack(['address', 'bool'], [poolAddresses[1], true]);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    let votes = await vxPremia.getUserVotes(alice.address);

    expect(votes.length).to.eq(2);

    expect(votes[0].target).to.eq(target1);
    expect(votes[0].amount).to.eq(parseEther('7'));

    expect(votes[1].target).to.eq(target2);
    expect(votes[1].amount).to.eq(parseEther('3'));

    await vxPremia.connect(deployer).resetUserVotes(alice.address);

    votes = await vxPremia.getUserVotes(alice.address);
    expect(votes.length).to.eq(0);
  });

  it('should fail resetting user votes if not called from owner', async () => {
    const { vxPremia, alice } = await loadFixture(deploy);

    await expect(
      vxPremia.connect(alice).resetUserVotes(alice.address),
    ).to.be.revertedWithCustomError(vxPremia, 'Ownable__NotOwner');
  });
});
