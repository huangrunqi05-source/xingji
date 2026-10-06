import {sqliteTable,text,index} from 'drizzle-orm/sqlite-core';
export const visits=sqliteTable('visits',{id:text('id').primaryKey(),owner:text('owner').notNull(),placeKey:text('place_key').notNull(),arrived:text('arrived').notNull(),payload:text('payload').notNull()},t=>[index('idx_visits_owner_arrived').on(t.owner,t.arrived)]);
export const photos=sqliteTable('photos',{id:text('id').primaryKey(),owner:text('owner').notNull(),visitId:text('visit_id').notNull(),objectKey:text('object_key').notNull()},t=>[index('idx_photos_owner_visit').on(t.owner,t.visitId)]);
export const lists=sqliteTable('lists',{id:text('id').primaryKey(),owner:text('owner').notNull(),title:text('title').notNull(),created:text('created').notNull()},t=>[index('idx_lists_owner').on(t.owner)]);
export const items=sqliteTable('items',{id:text('id').primaryKey(),owner:text('owner').notNull(),listId:text('list_id').notNull(),payload:text('payload').notNull()},t=>[index('idx_items_owner_list').on(t.owner,t.listId)]);
