// Fictional demo accounts inspired by public figures; never real user records.
export const COMP = 'demo-celebrity-2026';
export const PROJECT = 'dau-footy-tipping-f8a42';
export const NAMESPACE = `${PROJECT}-default-rtdb`;
export const roster = [
  ['albo', 'Albo', 'caricature'],
  ['rusty', 'Rusty', 'caricature'],
  ['hugh', 'Hugh Jackman', 'photo'],
  ['bana', 'Eric Bana', 'initials'],
  ['hughesy', 'Hughesy', 'caricature'],
  ['andy', 'Andy Lee', 'initials'],
  ['buddy', 'Buddy', 'photo'],
  ['dusty', 'Dusty', 'caricature'],
  ['bont', 'Marcus Bontempelli', 'initials'],
  ['daisy', 'Daisy', 'caricature'],
  ['erin', 'Erin Phillips', 'initials'],
  ['jt', 'JT', 'caricature'],
  ['joey', 'Andrew Johns', 'initials'],
  ['billy', 'Billy Slater', 'photo'],
  ['mary', 'Mary Fowler', 'photo'],
  ['sam', 'Sam Kerr', 'photo'],
  ['jess', 'Jess Mauboy', 'photo'],
  ['barty', 'Barty Party', 'caricature'],
  ['wendy', 'Wendy Harmer', 'initials'],
  ['ellie', 'Ellie Carpenter', 'photo'],
].map(([id, name, avatar]) => ({
  id, name, avatar, uid: `demo-celebrity-${id}`, tipperId: `demo-${id}`,
  email: `${id}@demo.example.test`,
}));
