export async function historyCacheRows(page) {
  return page.evaluate(() => new Promise((resolve, reject) => {
    const request = indexedDB.open('seekmoon.cloud-history.v1', 1);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const read = db.transaction('pages').objectStore('pages').getAll();
      read.onsuccess = () => resolve(read.result);
      read.onerror = () => reject(read.error);
      read.transaction.oncomplete = () => db.close();
    };
  }));
}
