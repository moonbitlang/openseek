export async function historyCacheRows(page, store = 'minimalPages') {
  return page.evaluate(store => new Promise((resolve, reject) => {
    const request = indexedDB.open('seekmoon.cloud-history.v1');
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const read = db.transaction(store).objectStore(store).getAll();
      read.onsuccess = () => resolve(read.result);
      read.onerror = () => reject(read.error);
      read.transaction.oncomplete = () => db.close();
    };
  }), store);
}
