import { useEffect, useState } from 'react';
import Bench from './bench/Bench';
import { loadInit } from './init';
import Tablet from './tablet/Tablet';

export default function App() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    loadInit().then(() => setReady(true));
  }, []);

  if (!ready) return null;

  return (
    <>
      <Bench />
      <Tablet />
    </>
  );
}
