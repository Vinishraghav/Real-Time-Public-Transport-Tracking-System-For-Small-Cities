import { initializeApp } from 'firebase/app';
import { getFirestore, collection, getDocs, query, where } from 'firebase/firestore';
const app = initializeApp({apiKey:'AIzaSyC7Ty__ev7Aw7IG_QIff1BcQE2bBGWps2k',authDomain:'citybus-live.firebaseapp.com',projectId:'citybus-live',storageBucket:'citybus-live.firebasestorage.app',messagingSenderId:'343570716967',appId:'1:343570716967:web:b32e743db9a98f32257102'});
const db = getFirestore(app);
for (const [name, field, value] of [['drivers','bus_number','TN38AB1234'],['buses','bus_number','TN38AB1234'],['users','bus_number','TN38AB1234']]) {
  const snap = await getDocs(query(collection(db,name), where(field,'==',value)));
  console.log('COLLECTION', name);
  console.log(JSON.stringify(snap.docs.map(d=>({id:d.id,...d.data()})), null, 2));
}
process.exit(0);
