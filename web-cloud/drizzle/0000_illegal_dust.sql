CREATE TABLE `items` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`list_id` text NOT NULL,
	`payload` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_items_owner_list` ON `items` (`owner`,`list_id`);--> statement-breakpoint
CREATE TABLE `lists` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`title` text NOT NULL,
	`created` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_lists_owner` ON `lists` (`owner`);--> statement-breakpoint
CREATE TABLE `photos` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`visit_id` text NOT NULL,
	`object_key` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_photos_owner_visit` ON `photos` (`owner`,`visit_id`);--> statement-breakpoint
CREATE TABLE `visits` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`place_key` text NOT NULL,
	`arrived` text NOT NULL,
	`payload` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_visits_owner_arrived` ON `visits` (`owner`,`arrived`);