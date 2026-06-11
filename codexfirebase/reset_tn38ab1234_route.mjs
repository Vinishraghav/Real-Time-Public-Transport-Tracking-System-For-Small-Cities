import { initializeApp } from 'firebase/app';
import {
  getAuth,
  signInWithEmailAndPassword,
} from 'firebase/auth';
import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  getFirestore,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const firebaseConfig = {
  apiKey: 'AIzaSyC7Ty__ev7Aw7IG_QIff1BcQE2bBGWps2k',
  authDomain: 'citybus-live.firebaseapp.com',
  projectId: 'citybus-live',
  storageBucket: 'citybus-live.firebasestorage.app',
  messagingSenderId: '343570716967',
  appId: '1:343570716967:web:b32e743db9a98f32257102',
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

const busNumber = 'TN38AB1234';
const routeId = 'R_SENJERI_SRIESHWAR_KINATHUKADAVU';

const stops = [
  {
    id: 'STOP_SENJERIMALAI',
    stop_name: 'Senjerimalai',
    latitude: 10.8326617,
    longitude: 77.1944859,
    route_id: routeId,
    order: 1,
  },
  {
    id: 'STOP_SRI_ESHWAR',
    stop_name: 'Sri Eshwar College of Engineering',
    latitude: 10.8265747,
    longitude: 77.0601786,
    route_id: routeId,
    order: 2,
  },
  {
    id: 'STOP_KINATHUKADAVU',
    stop_name: 'Kinathukadavu',
    latitude: 10.8284322,
    longitude: 77.0254459,
    route_id: routeId,
    order: 3,
  },
];

async function deleteQueryDocs(ref) {
  const snap = await getDocs(ref);
  await Promise.all(snap.docs.map((entry) => deleteDoc(entry.ref)));
  return snap.size;
}

async function main() {
  await signInWithEmailAndPassword(
    auth,
    'passenger@citybus.live',
    'Passenger@1234',
  );

  const busQuery = query(
    collection(db, 'buses'),
    where('bus_number', '==', busNumber),
  );
  const busSnap = await getDocs(busQuery);
  if (busSnap.empty) {
    throw new Error(`Bus ${busNumber} not found in Firestore.`);
  }

  const busDoc = busSnap.docs[0];
  const oldRouteId = busDoc.data().route_id || null;

  if (oldRouteId && oldRouteId !== routeId) {
    await deleteDoc(doc(db, 'routes', oldRouteId)).catch(() => {});
    await deleteDoc(doc(db, 'route_paths', oldRouteId)).catch(() => {});
    await deleteQueryDocs(
      query(collection(db, 'stops'), where('route_id', '==', oldRouteId)),
    );
    await deleteQueryDocs(
      query(collection(db, 'trips'), where('route_id', '==', oldRouteId)),
    );
    await deleteQueryDocs(
      query(collection(db, 'rides'), where('route_id', '==', oldRouteId)),
    );
  }

  await setDoc(doc(db, 'routes', routeId), {
    route_name: 'Senjerimalai -> Sri Eshwar College -> Kinathukadavu',
    start_stop: stops[0].id,
    end_stop: stops[2].id,
    stops: stops.map((stop) => stop.id),
    updated_at: serverTimestamp(),
  });

  await Promise.all(
    stops.map((stop) =>
      setDoc(doc(db, 'stops', stop.id), {
        ...stop,
        updated_at: serverTimestamp(),
      }),
    ),
  );

  await setDoc(
    doc(db, 'route_paths', routeId),
    {
      points: [],
      updated_at: serverTimestamp(),
    },
    { merge: true },
  );

  await updateDoc(busDoc.ref, {
    route_id: routeId,
    status: 'active',
    updated_at: serverTimestamp(),
  });

  const driverSnap = await getDocs(
    query(collection(db, 'drivers'), where('bus_number', '==', busNumber)),
  );
  await Promise.all(
    driverSnap.docs.map((driverDoc) =>
      updateDoc(driverDoc.ref, {
        route_id: routeId,
        updated_at: serverTimestamp(),
      }),
    ),
  );

  const usersSnap = await getDocs(
    query(collection(db, 'users'), where('bus_number', '==', busNumber)),
  );
  await Promise.all(
    usersSnap.docs.map((userDoc) =>
      updateDoc(userDoc.ref, {
        route_id: routeId,
        updated_at: serverTimestamp(),
      }),
    ),
  );

  await setDoc(
    doc(db, 'live_buses', busNumber),
    {
      bus_id: busNumber,
      latitude: 0,
      longitude: 0,
      speed: 0,
      heading: 0,
      trip_status: 'ended',
      last_updated: serverTimestamp(),
    },
    { merge: true },
  );

  console.log(
    JSON.stringify(
      {
        ok: true,
        busNumber,
        oldRouteId,
        newRouteId: routeId,
        stops: stops.map((stop) => stop.stop_name),
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
