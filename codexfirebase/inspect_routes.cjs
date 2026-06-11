const { initializeApp } = require('firebase/app');
const { getFirestore, collection, getDocs, query, where, doc, getDoc } = require('firebase/firestore');
(async()=>{
const app=initializeApp({apiKey:'AIzaSyC7Ty__ev7Aw7IG_QIff1BcQE2bBGWps2k',authDomain:'citybus-live.firebaseapp.com',projectId:'citybus-live',storageBucket:'citybus-live.firebasestorage.app',messagingSenderId:'343570716967',appId:'1:343570716967:web:b32e743db9a98f32257102'});
const db=getFirestore(app);
const routeIds=['route_cbe_f','route_cbe_r','R_SENJERI_SRIESHWAR_KINATHUKADAVU'];
for (const routeId of routeIds){
  const routeDoc=await getDoc(doc(db,'routes',routeId));
  const stopSnap=await getDocs(query(collection(db,'stops'), where('route_id','==',routeId)));
  const pathDoc=await getDoc(doc(db,'route_paths',routeId));
  console.log('ROUTE', routeId, JSON.stringify({route: routeDoc.exists()?routeDoc.data():null, stops: stopSnap.docs.map(d=>({id:d.id,...d.data()})), path:pathDoc.exists()?pathDoc.data():null}, null, 2));
}
process.exit(0);
})().catch(e=>{console.error(e);process.exit(1);});
