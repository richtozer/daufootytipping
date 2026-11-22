// scripts/slim_auth_export.mjs: the function that reduces a `firebase auth:export` to uid, email and verified flag.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { slimAuthExport } from '../scripts/slim_auth_export.mjs';

const full = {
  users: [
    {
      localId: 'uid-b',
      email: 'b@example.com',
      emailVerified: true,
      passwordHash: 'HASH-B',
      salt: 'SALT-B',
      passwordUpdatedAt: 1,
      providerUserInfo: [{ providerId: 'password', rawId: 'b@example.com' }],
    },
    { localId: 'uid-a', emailVerified: false, passwordHash: 'HASH-A' },
    { uid: 'uid-c', email: '', emailVerified: 'yes' },
    { email: 'no-uid@example.com' },
    { localId: '' },
    null,
  ],
};

describe('slimAuthExport', () => {
  it('keeps only uid, email and emailVerified, sorted by uid', () => {
    assert.deepEqual(slimAuthExport(full), {
      users: [
        { uid: 'uid-a', emailVerified: false },
        { uid: 'uid-b', email: 'b@example.com', emailVerified: true },
        { uid: 'uid-c', emailVerified: false },
      ],
    });
  });

  it('leaves no password hash, salt or provider detail anywhere in the result', () => {
    const text = JSON.stringify(slimAuthExport(full));
    for (const secret of ['HASH-A', 'HASH-B', 'SALT-B', 'passwordHash', 'salt', 'providerUserInfo', 'rawId']) {
      assert.ok(!text.includes(secret), `${secret} leaked into the slim file`);
    }
  });

  it('treats anything but a users list as empty', () => {
    assert.deepEqual(slimAuthExport({}), { users: [] });
    assert.deepEqual(slimAuthExport(null), { users: [] });
    assert.deepEqual(slimAuthExport({ users: 'nope' }), { users: [] });
  });
});
