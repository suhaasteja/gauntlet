class Database {
  subscriptions = {
    insert: async (data: any) => {
      console.log('Inserting subscription:', data);
      return { id: 'sub_123', ...data };
    },
    update: async (filter: any, data: any) => {
      console.log('Updating subscription:', filter, data);
      return { modified: 1 };
    },
    find: async (filter: any) => {
      return [];
    }
  };

  transactions = {
    insert: async (data: any) => {
      console.log('Inserting transaction:', data);
      return { id: 'txn_123', ...data };
    },
    find: (filter: any) => ({
      sort: (sortBy: any) => Promise.resolve([])
    })
  };
}

export const db = new Database();
