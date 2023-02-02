import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';

import moment from 'moment-timezone';
moment.tz.setDefault('UTC');

export const ONE_HOUR = 3600;
export const ONE_DAY = 24 * ONE_HOUR;
export const ONE_WEEK = 7 * ONE_DAY;
export const ONE_MONTH = 30 * ONE_DAY;
export const ONE_YEAR = 365 * ONE_DAY;

// returns the current timestamp
export async function now() {
  return (await ethers.provider.getBlock('latest')).timestamp;
}

// Increases ganache time by the passed duration in seconds
export async function increase(duration: number | BigNumber) {
  if (!BigNumber.isBigNumber(duration)) {
    duration = BigNumber.from(duration);
  }

  if (duration.lt(BigNumber.from('0')))
    throw Error(`Cannot increase time by a negative amount (${duration})`);

  await ethers.provider.send('evm_increaseTime', [duration.toNumber()]);
  await ethers.provider.send('evm_mine', []);
}

/**
 * Beware that due to the need of calling two separate ganache methods and rpc calls overhead
 * it's hard to increase time precisely to a target point so design your test to tolerate
 * small fluctuations from time to time.
 *
 * @param target time in seconds
 */
export async function increaseTo(target: number | BigNumber) {
  if (!BigNumber.isBigNumber(target)) {
    target = BigNumber.from(target);
  }

  const now = BigNumber.from(
    (await ethers.provider.getBlock('latest')).timestamp,
  );

  if (target.lt(now))
    throw Error(
      `Cannot increase current time (${now}) to a moment in the past (${target})`,
    );

  const diff = target.sub(now);
  return increase(diff);
}

export async function getLastFridayOfMonth(timestamp: number, interval: any) {
  const currentTime = moment.unix(timestamp);

  const lastDayOfMonth = moment(currentTime.add(interval, 'months'))
    .endOf('month')
    .startOf('day');

  let friday;

  if (lastDayOfMonth.day() == 6) {
    friday = lastDayOfMonth.subtract(1, 'days');
  } else {
    friday = lastDayOfMonth.subtract(lastDayOfMonth.day() + 2, 'days');
  }

  return friday.hour(8).unix();
}

export async function getValidMaturity(interval: any, period: string) {
  const timestamp = await now();
  const currentTime = moment.unix(timestamp);

  if (period === 'days' && interval < 3) {
    return moment(currentTime.add(interval, 'days'))
      .startOf('day')
      .hour(8)
      .unix();
  } else if (period === 'weeks' && interval <= 4) {
    return moment(currentTime.add(interval, 'weeks'))
      .startOf('isoWeek')
      .day('friday')
      .hour(8)
      .unix();
  } else if (period === 'months' && interval <= 12) {
    return await getLastFridayOfMonth(timestamp, interval);
  }

  throw new Error('Invalid Maturity Parameters');
}

export async function takeSnapshot() {
  const snapshotId: string = await ethers.provider.send('evm_snapshot', []);
  return snapshotId;
}

export async function revertToSnapShot(id: string) {
  await ethers.provider.send('evm_revert', [id]);
}

export function revertToSnapshotAfterEach(
  beforeEachCallback = async () => {},
  afterEachCallback = async () => {},
) {
  let snapshotId: string;

  beforeEach(async function () {
    snapshotId = await takeSnapshot();
    await beforeEachCallback.bind(this)();
  });
  afterEach(async () => {
    await afterEachCallback.bind(this)();
    await revertToSnapShot(snapshotId);
  });
}
