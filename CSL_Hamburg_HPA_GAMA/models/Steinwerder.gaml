/***
* Name: Steinwerder
* Author: JLopez
* Description: simple model, that uses the moving skill - no accounting of people collision
***/

model Steinwerder

global {
	string cityGISFolder <- "/external/Steinwerder/";
	
	file shapefile_buildings <- file(cityGISFolder + "Buildings.shp");
	file shapefile_entrance <- file(cityGISFolder + "entrance.shp");
	file shapefile_exit <- file(cityGISFolder + "exit.shp");
	file<geometry> shapefile_roads <- shape_file(cityGISFolder + "Roads.shp");
	file<geometry> pedestrian_paths <- shape_file(cityGISFolder + "Pedestrian_paths.shp");
	file boundary <- file(cityGISFolder + "Bounds.shp");
	file road_traffic_origin <- file(cityGISFolder + "traffic_access.shp");
	file road_traffic_destination <- file(cityGISFolder + "traffic_exit.shp");
	file shapefile_boarding <- file(cityGISFolder + "boarding.shp");
	file shapefile_checkin_stand <- file(cityGISFolder + "checkin_stand.shp");
	file shapefile_card_collection_stand <- file(cityGISFolder + "card_collection_stand.shp");
	file shapefile_security_stand <- file(cityGISFolder + "security_stand.shp");
	file desk_spots <- file(cityGISFolder + "desk_spot.shp");			
	
	file shapefile_taxi_stand <- file(cityGISFolder + "Taxi_spot.shp");
	file shapefile_car_stand <- file(cityGISFolder + "car_spot.shp");
	file crew_lug_spots <- file(cityGISFolder + "crew_spots.shp");
	file shapefile_shuttle <- file(cityGISFolder + "bus shuttle.shp");
	
	file site_plan <- image_file(cityGISFolder + "Site Plan.png");

	geometry shape <- envelope(boundary);
	graph network;
	graph network_traffic;

	float step <- 2#s;
	int cruise_size; // this should be taken from the CSV with traffic_destination schedules
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	
	float people_disembarking_freq;
	float people_boarding_freq;
	float shuttle_freq;
	int current_hour <- 7; //starting hour of the simulation
	int current_day <-1;
	int nb_tourist;
	int nb_people;
	float terminal_arrival_choice;
	float hamburg_arrival_choice;
	string time_info;
	
	int people_in_terminal;
	int people_boarded_vessel;
	int people_passed_security;
	int people_passed_checkin;
	int people_collected_card;
	int people_left_terminal;
	
	int nb_taxis update: length(taxi);
	int nb_cars update: length(car);
	int nb_shuttles update: length(shuttle);
	int nb_disembarking update: (length(tourist_car)+length(tourist_taxi)+length(tourist_shuttle));
	int nb_boarding update: length(tourist_arriving_generic);
	int avg_waiting_time update: tourist_arriving_car_taxi sum_of(each.waiting_time_dropoff);
	
	reflex time_update when: every(1#hour) {
		current_hour <- current_hour +1;
		if current_hour > 16{
			current_hour <- 5;
			current_day <- current_day+1;
		}
		time_info <- "Day: " + string (current_day) + " Hour: " + string(current_hour) + ":00" ;
	}
	
	reflex update {
		nb_taxis <- length(taxi);
		nb_cars <- length(car);
		nb_shuttles <- length(shuttle);
		nb_disembarking <- (length(tourist_car)+length(tourist_taxi)+length(tourist_shuttle));
		nb_boarding <- length(tourist_arriving_generic);
		avg_waiting_time <- tourist_arriving_car_taxi sum_of(each.waiting_time_dropoff);
	}
	
	reflex time_peaks { 				//adjusted to IG activeness curve
		if current_hour < 7{
			people_disembarking_freq <- 0.0;
			people_boarding_freq <- 0.0;
		}
		if current_hour = 7 {
			people_disembarking_freq <- 3.0;	
			people_boarding_freq <- 0.0;
		}
		if current_hour = 8{
			people_disembarking_freq <- 10.0;	
			people_boarding_freq <- 0.0;
		}
		if current_hour = 9{
			people_disembarking_freq <- 50.0;	
			people_boarding_freq <- 0.0;
		}
		if current_hour = 10{
			people_disembarking_freq <- 100.0;	
			people_boarding_freq <- 500.0;
		}
		if current_hour = 11{
			people_disembarking_freq <- 1000.0;	
			people_boarding_freq <- 300.0;
		}
		if current_hour = 12{
			people_disembarking_freq <- 1000.0;	
			people_boarding_freq <- 100.0;
		}
		if current_hour = 13{
			people_disembarking_freq <- 1500.0;	
			people_boarding_freq <- 75.0;
		}
		if current_hour = 14{
			people_disembarking_freq <- 0.0;	
			people_boarding_freq <- 150.0;
		}
		if current_hour = 15{
			people_disembarking_freq <- 0.0;	
			people_boarding_freq <- 500.0;
		}
		if current_hour > 15{
			people_disembarking_freq <- 0.0;	
			people_boarding_freq <- 0.0;
		}
	}
	
	reflex refill{ //this ensures at least one transportation mean of each: to avoid nil destination in tourist_arriving
		if (nb_taxis)<3{
			create taxi from: shapefile_taxi_stand number:1;
		}
		if (nb_shuttles)<2{
			create shuttle from: shapefile_shuttle number:1;
		}
		if (nb_cars)<2{
			create car_leaving from: shapefile_car_stand number:1;
		}
	}
	
	init{	
		create buildings from:shapefile_buildings with:[height:int(read("Height"))];	
		create shuttle_spot from: shapefile_shuttle;
		create exit from: shapefile_exit;
		create car_spot from: shapefile_car_stand;
		
		free_space <- free_space simplification(1.0);
		create obstacle from:(shape - free_space).geometries;
		create shuttle from:shapefile_shuttle number:5;


		create pedestrian_path from:pedestrian_paths;
		network <- as_edge_graph(pedestrian_path);	 
		create traffic_road from:shapefile_roads;
		network_traffic <- as_edge_graph(traffic_road);
		
		create traffic_origin from:road_traffic_origin;
		create traffic_destination from:road_traffic_destination;
		create taxi from:shapefile_taxi_stand number:15;
		create taxi_spot from:shapefile_taxi_stand;
		create entrance from:shapefile_entrance;
		create tourist_car from:shapefile_exit;
		create tourist_shuttle from:shapefile_exit;
		create tourist_taxi from:shapefile_exit;
		create car_leaving number:int(cruise_size*0.3) from:shapefile_car_stand;
		create boarding_spot from: shapefile_boarding;
		
		create checkin_stand from: shapefile_checkin_stand;
		create card_stand from: shapefile_card_collection_stand;
		create security_stand from: shapefile_security_stand;
		create crew_lug_spot from:crew_lug_spots;
		create desk_spot from: desk_spots;
		create desk from: desk_spots;
		
		create crew_lug from: crew_lug_spots {
			spot <- one_of(crew_lug_spot where (each.current_crew_lug = nil));
			spot.current_crew_lug <- self;
			location <- spot.location;
		}
		create crew_card from: shapefile_card_collection_stand{
			spot <- one_of(card_stand where (each.current_crew_card = nil));
			spot.current_crew_card <- self;
			location <- spot.location;
		}

		create crew_security from: shapefile_security_stand{
			spot <- one_of(security_stand where (each.current_crew_security = nil));
			spot.current_crew_security <- self;
			location <- spot.location;
		}

		create crew_checkin from: shapefile_checkin_stand{
			spot <- one_of(checkin_stand where (each.current_crew_checkin = nil));
			spot.current_crew_checkin <- self;
			location <- spot.location;
		}

	}
}
species traffic_destination{}
species traffic_road{} 
species terminal_flow{}
species exit{}
species roads{}
species entrance{}
species pedestrian_path {}

species buildings{
	int height;
	aspect default {
		//draw shape color: rgb(120,125,130) depth:(height*4);
		draw shape color:#gray empty:true width:0.5;
	}
}
species obstacle {
	geometry free_space;
}
species boarding_spot{
int number<-rnd(1);
	reflex people_exit when: every((people_disembarking_freq*4)#cycle){
			create tourist_car number: (number+rnd(3)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			}	
			create tourist_shuttle number: (number) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			}
			create tourist_taxi number: (rnd(1)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;	
			}
	}
}
species traffic_origin{
	reflex create_taxis when: every(people_disembarking_freq*50#cycle){
		create taxi_arriving number: rnd(1,2) with: [location::location];
	}
	reflex create_cars when: every(people_boarding_freq#cycle){
		create car_arriving number: rnd(1,5) with: [location::location];
		create taxi_arriving number: rnd(1,3) with: [location::location];
		create shuttle_arriving number: rnd(1) with: [location::location];
	}
}
species car skills: [moving] control:fsm{}
species car_arriving parent: car{
	point final_target <- point(one_of(car_spot));
	reflex end when: (location distance_to final_target) <= 5{
		create car_leaving number:1 with:[location::location];
		create tourist_arriving_car_taxi number:rnd(4) with:[location::location];
		do die;
	}

	reflex move {
		do goto target: final_target on: network_traffic speed:15#km/#h;
	}
			
	aspect default {
		draw rectangle(4,1.5) color:#white rotate:heading;
	}
}

species car_leaving parent:car{
	point final_target;
	bool has_passenger;
	int tourist_capacity<-1;
	int luggage_capacity<-rnd(2,5);
	
	action leave {
		do goto target: final_target on: network_traffic speed:15#km/#h;
		if location distance_to final_target <= 5{
			do die;
		}
	}
	
	state parked initial:true{
		enter{
			heading <- 45.0;
		}
		transition to:going when: tourist_capacity < 1;
	}
	
	state going{
		enter{
			final_target<- point(one_of(traffic_destination));
		}
		do leave;
	}	
		
	aspect default {
		draw rectangle(4,1.5) color:#white rotate:heading;
	}
}
species car_spot control:fsm{
	state unavailable {
		transition to: available when: location distance_to point(one_of(car_leaving)) >= 3;
	}
	
	state available initial:true{
		transition to:unavailable when: location distance_to point(one_of(car_leaving)) < 3;
	}
}
species taxi_spot control:fsm{
	state unavailable {
		transition to: available when: (location distance_to point(one_of(taxi)) >= 3);
	}
	
	state available initial:true{
		transition to:unavailable when: (location distance_to point(one_of(taxi)) < 3);
	}
}
species taxi_arriving skills:[moving]{
	point final_target<-point(one_of(taxi_spot));
	reflex end when: (location distance_to final_target) <= 5{
		create taxi number:1 with:[location::location];
		create tourist_arriving_car_taxi number:rnd(3) with:[location::location];
		do die;
	}

	reflex move {
		do goto target: final_target on: network_traffic speed:15#km/#h;
	}
			
	aspect default {
		draw rectangle(4,1.5) color:#red rotate:heading;
	}
}
species taxi skills:[moving] control:fsm {
	point final_target;
	bool has_passenger;
	int tourist_capacity<-rnd(3,5);
	
	action leave {
		do goto target: final_target on: network_traffic speed:15#km/#h;
		if location distance_to final_target <= 5{
			do die;
		}
	}
	
	state parked initial:true{
		enter{
			heading <- -45.0;
		}
		transition to:going when: tourist_capacity < 1;
	}
	
	state going{
		enter{
			final_target<- point(one_of(traffic_destination));
		}
		do leave;
	}		
		
	aspect default {
		draw rectangle(4,1.5) color:#white rotate:heading;
	}
}

species crew_lug_spot{
	crew_lug current_crew_lug;
	list<tourist_arriving_car_taxi> waiting_tourists;
	int queue_length;
	reflex update_lengh{
		queue_length <- length(list(waiting_tourists));	
	}
	
	aspect base {
		int i<-0;
		loop t over:waiting_tourists{
			draw circle (0.5) at:{t.location.x+i,t.location.y-i} color:rgb(246,232,198) ;
			i<-i+1;	
		}
	} 
}
species checkin_stand {
	crew_checkin current_crew_checkin;
	list<tourist_arriving_generic> waiting_tourists_checkin;
	int queue_length;
	reflex update_lengh{
		queue_length <- length(list(waiting_tourists_checkin));	
	}
	
	aspect base {
		int i<-0;
		loop t over:waiting_tourists_checkin{
			draw circle (0.5) at:{t.location.x-i,t.location.y-i} color:rgb(246,232,198) ;
			i<-i+1;	
		}
	} 
}
species card_stand {
	crew_card current_crew_card;
	list<tourist_arriving_generic> waiting_tourists_card;
	int queue_length;
	reflex update_lengh{
		queue_length <- length(list(waiting_tourists_card));	
	}
	aspect base {
		int i<-0;
		loop t over:waiting_tourists_card{
			draw circle (0.5) at:{t.location.x+i,t.location.y-i} color:rgb(246,232,198) ;
			i<-i+1;	
		}
	} 
}
species security_stand {
	crew_security current_crew_security;
	list<tourist_arriving_generic> waiting_tourists_security;
	int queue_length;
	reflex update_lengh{
		queue_length <- length(list(waiting_tourists_security));	
	}
	aspect base {
		int i<-0;
		loop t over:waiting_tourists_security{
		draw circle (0.5) at:{t.location.x+i,t.location.y+i} color:rgb(246,232,198) ;
			i<-i+1;	
		}
	} 
}

species desk_spot control:fsm{
	state unavailable {
		transition to: available when: location distance_to one_of(desk) >= 1;
	}
	
	state available initial:true{
		transition to:unavailable when: location distance_to one_of(desk) < 1;
	}
	
	aspect default {
		draw circle(3) color: #cyan;
	}
}

species shuttle_spot control:fsm {
	crew_lug current_crew_lug;
	rgb color <- #blue;	

	state unavailable {
		transition to: available when: location distance_to one_of(shuttle) >= 1;
	}
	
	state available initial:true{
		transition to:unavailable when: location distance_to one_of(shuttle) < 1;
	}

	aspect base {
		draw circle(3) color:rgb(179,186,196);
		}
}

species shuttle skills:[moving] control:fsm {
	point final_target;
	bool has_passenger;
	int tourist_capacity<-rnd(40,50);
	int luggage_capacity<-rnd(40,50);
	
	action leave {
		do goto target: final_target on: network_traffic speed:15#km/#h;
		if location distance_to final_target <= 5{
			do die;
		}
	}
	
	state parked initial:true{
		enter{
			heading <- 0.0;
		}
		transition to:going when: tourist_capacity < 1;
	}
	
	state going{
		enter{
			final_target<- point(one_of(traffic_destination));
		}
		do leave;
	}	

	aspect base {
		draw rectangle(10,2) color:#pink rotate:heading;
	}
}

species shuttle_arriving skills:[moving]{
	point final_target<-point(one_of(shuttle_spot));
	reflex end when: (location distance_to final_target) <= 5{
		create shuttle number:1 with:[location::location];
		create tourist_arriving_generic number:rnd(10,30) with:[location::(point(location.x+rnd(15),location.y+rnd(15)))];
		do die;
	}

	reflex move {
		do goto target: final_target on: network_traffic speed:15#km/#h;
	}
			
	aspect default {
		draw rectangle(10,2) color:#red rotate:heading;
	}
}

species desk control:fsm{ //no needed for this simulation
	int luggage_capacity;
	state loading initial:true{
	}
}

species crew_lug skills:[moving] control:fsm {
	point target_loc;
	crew_lug_spot spot;
	int carrying_luggage;
	tourist_arriving_car_taxi current_tourist;
	desk current_desk;
	rgb color;
	
	action carry_luggage{
		if ((current_desk = nil) or (current_desk.state != "loading")) {
			list<desk> available_desk <- desk where (each.state = 'loading');
			if not empty(available_desk) {
				current_desk <- available_desk closest_to self;
				target_loc <- current_desk.location;
			}
		}
		
		if (target_loc != nil) {
			do goto target: target_loc;
			if location distance_to target_loc < 1 {
				current_desk.luggage_capacity <- current_desk.luggage_capacity - carrying_luggage;
				carrying_luggage <- 0;
				current_desk <- nil;
				target_loc <- nil;
			}
		}
	}
	
	state go_back_spot {
		enter {
			color <- #red;
		}
		do goto target:spot;
		transition to: available  when: location = spot.location;
	}
	
	state go_to_desk {
		enter {
			current_tourist <- first(spot.waiting_tourists);
			remove current_tourist from: spot.waiting_tourists;
			carrying_luggage <- current_tourist.luggage_count;
			current_tourist.dropped_luggage <- true;
			current_tourist.luggage_count <- 0;
			color <- #red;
			target_loc <- nil;
		}
		do carry_luggage;
		
		transition to: go_back_spot when: carrying_luggage = 0;
	}
	
	state available initial:true{
		enter{
			color <- #pink;
		}
		transition to: go_to_desk when: not empty(spot.waiting_tourists);
	}
	aspect default {
		draw circle(0.5) color:color;
	}
}
species crew_card skills:[moving] control:fsm {
	point target_loc;
	card_stand spot;
	int carrying_luggage;
	tourist_arriving_generic current_tourist;
	desk current_desk;
	rgb color;
	
	action register{
		if ((current_desk = nil) or (current_desk.state != "loading")) {
			list<desk> available_desk <- desk where (each.state = 'loading');
			if not empty(available_desk) {
				current_desk <- available_desk closest_to self;
				target_loc <- current_desk.location;
			}
		}
		
		if (target_loc != nil) {
			do goto target: target_loc;
			if location distance_to target_loc < 1 {
				current_desk.luggage_capacity <- current_desk.luggage_capacity - carrying_luggage;
				carrying_luggage <- 0;
				current_desk <- nil;
				target_loc <- nil;
			}
		}
	}
	
	state go_back_spot {
		enter {
			color <- #red;
		}
		do goto target:spot;
		transition to: available  when: location = spot.location;
	}
	
	state go_to_desk {
		enter {
			current_tourist <- first(spot.waiting_tourists_card);
			remove current_tourist from: spot.waiting_tourists_card;
			carrying_luggage <- 1;
			current_tourist.third_card_collection <- true;
			color <- #red;
			target_loc <- nil;
		}
		do register;
		
		transition to: go_back_spot when: carrying_luggage = 0;
	}
	
	state available initial:true{
		enter{
			color <- #pink;
		}
		transition to: go_to_desk when: not empty(spot.waiting_tourists_card);
	}
	aspect default {
		draw circle(0.5) color:color;
	}
}
species crew_checkin skills:[moving] control:fsm {	
	point target_loc;
	checkin_stand spot;
	int carrying_luggage;
	tourist_arriving_generic current_tourist;
	desk current_desk;
	rgb color;
	
	action register{
		if ((current_desk = nil) or (current_desk.state != "loading")) {
			list<desk> available_desk <- desk where (each.state = 'loading');
			if not empty(available_desk) {
				current_desk <- available_desk closest_to self;
				target_loc <- current_desk.location;
			}
		}
		
		if (target_loc != nil) {
			do goto target: target_loc;
			if location distance_to target_loc < 1 {
				current_desk.luggage_capacity <- current_desk.luggage_capacity - carrying_luggage;
				carrying_luggage <- 0;
				current_desk <- nil;
				target_loc <- nil;
			}
		}
	}
	
	state go_back_spot {
		enter {
			color <- #red;
		}
		do goto target:spot;
		transition to: available  when: location = spot.location;
	}
	
	state go_to_desk {
		enter {
			current_tourist <- first(spot.waiting_tourists_checkin);
			remove current_tourist from: spot.waiting_tourists_checkin;
			carrying_luggage <- 1;
			current_tourist.second_checkin <- true;
			color <- #red;
			target_loc <- nil;
		}
		do register;
		
		transition to: go_back_spot when: carrying_luggage = 0;
	}
	
	state available initial:true{
		enter{
			color <- #pink;
		}
		transition to: go_to_desk when: not empty(spot.waiting_tourists_checkin);
	}
	aspect default {
		draw circle(0.5) color:color;
	}
}
species crew_security skills:[moving] control:fsm {
	point target_loc;
	security_stand spot;
	int carrying_luggage;
	tourist_arriving_generic current_tourist;
	desk current_desk;
	rgb color;
	
	action register{
		if ((current_desk = nil) or (current_desk.state != "loading")) {
			list<desk> available_desk <- desk where (each.state = 'loading');
			if not empty(available_desk) {
				current_desk <- available_desk closest_to self;
				target_loc <- current_desk.location;
			}
		}
		
		if (target_loc != nil) {
			do goto target: target_loc;
			if location distance_to target_loc < 1 {
				current_desk.luggage_capacity <- current_desk.luggage_capacity - carrying_luggage;
				carrying_luggage <- 0;
				current_desk <- nil;
				target_loc <- nil;
			}
		}
	}
	
	state go_back_spot {
		enter {
			color <- #red;
		}
		do goto target:spot;
		transition to: available  when: location = spot.location;
	}
	
	state go_to_desk {
		enter {
			current_tourist <- first(spot.waiting_tourists_security);
			remove current_tourist from: spot.waiting_tourists_security;
			carrying_luggage <- 1;
			current_tourist.forth_security <- true;
			color <- #red;
			target_loc <- nil;
		}
		do register;
		
		transition to: go_back_spot when: carrying_luggage = 0;
	}
	
	state available initial:true{
		enter{
			color <- #pink;
		}
		transition to: go_to_desk when: not empty(spot.waiting_tourists_security);
	}
	aspect default {
		draw circle(0.5) color:color;
	}
}
species tourist_arriving_car_taxi skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	bool dropped_luggage;
	int luggage_count <- rnd(1)+1;
	bool dropping_now <- false;
	float waiting_time;
	int tourist_line;
	crew_lug_spot the_spot;
	list<crew_lug_spot> known_drop_off_areas;
	point final_target;
	shuttle current_shuttle;
	int start_waiting_time_dropoff;
	int end_waiting_time_dropoff;
	int waiting_time_dropoff;
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	
	reflex waiting_time{
		waiting_time_dropoff<-end_waiting_time_dropoff-start_waiting_time_dropoff;
		if waiting_time_dropoff < 0 {
			waiting_time_dropoff<-0;
		}
	}
	
	state goto_drop_off_luggage initial: true{
		enter {
			known_drop_off_areas <- crew_lug_spot  where (each.current_crew_lug != nil);
			the_spot <- (known_drop_off_areas where (each.queue_length = (min_of(known_drop_off_areas, each.queue_length)))) closest_to self;
			final_target <- the_spot.location;
		}
		do goto target: final_target on: network speed:speed;
		transition to: drop_off_luggage when: (self distance_to final_target) < 10.0;
	}
	
	state drop_off_luggage {
		enter {
			start_waiting_time_dropoff <- cycle;
			the_spot.waiting_tourists << self;
			dropping_now <- true;
		}
		transition to: go_to_entrance when: dropped_luggage;
	}
	state go_to_entrance {
		enter {
			end_waiting_time_dropoff <- cycle;
			dropping_now <- false;
			final_target <- point(one_of(entrance));
		}
		do goto target: final_target on: network speed:speed;
		if (location distance_to final_target) < 10.0  {
			people_in_terminal <-people_in_terminal+1;
			create tourist_arriving_generic with: [location::location] number:1;
			do die;
		}
	}
	
	aspect default {
		draw circle(0.5) at:{location.x+offsetx,location.y+offsety} color: #white;
		draw circle(3) at:{location.x+offsetx,location.y+offsety} empty:true width:0.5 color: #white;
	}
	aspect glow{
		draw circle(1) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species tourist_arriving_generic skills:[moving] control:fsm {
	point final_target;
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	float speed <-gauss(3,1) #km/#h min: 1.0;
	bool first_enter;
	bool second_checkin;
	bool third_card_collection;
	bool forth_security;
	bool fifth_board;
	int luggage_count <-1; //Symbolic
	
	checkin_stand spot_checkin;
	card_stand spot_card;
	security_stand spot_security;
	list<checkin_stand> known_checkin_stand;
	list<card_stand> known_card_stand;
	list<security_stand> known_security_stand;
	
	state board{
		final_target <- point(one_of(boarding_spot));

		do goto target: final_target speed:speed;
		if (location distance_to final_target) < 1.0  {
			people_boarded_vessel <-people_boarded_vessel+1;
			do die;
		}
	}
	
	state go_to_security{
			known_security_stand <- security_stand where (each.current_crew_security !=nil);
			spot_security <- (known_security_stand where (each.queue_length = (min_of(known_security_stand, each.queue_length)))) closest_to self;
			final_target <- spot_security.location;

		do goto target: final_target speed:speed;
		transition to:security_check when: (self distance_to final_target) < 1.0;
	}
	
	state security_check{
		enter  {
			spot_security.waiting_tourists_security << self;
			people_passed_security <-people_passed_security+1;
		}
		transition to:board when: forth_security;
	}
	
	state go_to_card_collection{
			known_card_stand <- card_stand where (each.current_crew_card !=nil);
			spot_card <- (known_card_stand where (each.queue_length = (min_of(known_card_stand, each.queue_length)))) closest_to self;
			final_target <- spot_card.location;

		do goto target: final_target speed:speed;
		transition to:card_check when: (self distance_to final_target) < 1.0;
	}
	state card_check{
		enter{
			spot_card.waiting_tourists_card << self;
			people_collected_card <-people_collected_card+1;
			}
		transition to:go_to_security when: third_card_collection;
	}
	
	state go_to_checkin{
			known_checkin_stand <- checkin_stand where (each.current_crew_checkin !=nil);
			spot_checkin <- (known_checkin_stand where (each.queue_length = (min_of(known_checkin_stand, each.queue_length)))) closest_to self;
			final_target <- spot_checkin.location;

		do goto target: final_target speed:speed;
		transition to:checkin_check when: (self distance_to final_target) < 1.0;
	}
	state checkin_check{
		enter{
			spot_checkin.waiting_tourists_checkin << self;
			people_passed_checkin <-people_passed_checkin+1;	
			}
	transition to:go_to_card_collection when: second_checkin;	
	}
	
	
	state go_to_entrance initial:true{
		enter {
			final_target <- point(one_of(entrance));
		}
		do goto target: final_target on: network speed:speed;
		if (location distance_to final_target) < 1.0  {
			people_in_terminal <-people_in_terminal+1;
			first_enter<-true;
		}
		transition to:go_to_checkin when: first_enter;
	}
	
	aspect default {
		draw circle(0.5) at:{location.x+offsetx,location.y+offsety} color: #gray;
	}
	aspect glow{
		draw circle(3) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species tourist_shuttle skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	int luggage_count <- rnd(2);
	point final_target;
	int offsetx <- rnd(3);
	int offsety <- rnd(3);
	shuttle_spot current_shuttle;
	
	action go_to_taxi{
		if ((current_shuttle = nil) or (current_shuttle.state != "available")) {
			list<shuttle_spot> available_shuttle <- shuttle_spot where (each.state = 'unavailable');
			if not empty(available_shuttle) {
				current_shuttle <- available_shuttle closest_to self;
				final_target <- current_shuttle.location;
			}
		}
		if (final_target != nil) {
			do goto target: final_target on:network;
			if location distance_to final_target < 1 {
				ask shuttle closest_to self{
					tourist_capacity <- tourist_capacity-1;
					has_passenger<-true;
				}
			people_left_terminal <- people_left_terminal+1;
			do die;
			}
		}
	}
	
	action go_to_exit{
		do goto target:point(one_of(exit)) on:network speed:speed;
	}

	state going_to_exit initial:true{
		do go_to_exit;
	transition to: going_to_taxi when: location distance_to point(one_of(exit))<=1;
	}
	
	state going_to_taxi {
		do go_to_taxi;
	}
	
	aspect default {
		draw circle(0.5) at:{location.x+offsetx,location.y+offsety} color: #white;
	}
	aspect glow{
		draw circle(3) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species tourist_car skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	int luggage_count <- rnd(2);
	point final_target;
	int offsetx <- rnd(3);
	int offsety <- rnd(3);
	car_spot current_car;
	
	action go_to_car{
		if ((current_car = nil) or (current_car.state != "available")) {
			list<car_spot> available_car <- car_spot where (each.state = 'unavailable');
			if not empty(available_car) {
				current_car <- available_car closest_to self;
				final_target <- current_car.location;
			}
		}
		if (final_target != nil) {
			do goto target: final_target on:network;
			if location distance_to final_target < 1 {
				ask car_leaving closest_to self{
					tourist_capacity <- tourist_capacity-1;
					has_passenger<-true;
				}
			people_left_terminal <- people_left_terminal+1;
			do die;
			}
		}
	}
	
	action go_to_exit{
		do goto target:point(one_of(exit)) on:network speed:speed;
	}

	state going_to_exit initial:true{
		do go_to_exit;
	transition to: going_to_car when: location distance_to point(one_of(exit))<=1;
	}
	
	state going_to_car {
		do go_to_car;
	}
	
	aspect default {
		draw circle(0.5) at:{location.x+offsetx,location.y+offsety} color: #gray;
	}
	aspect glow{
		draw circle(3) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species tourist_taxi skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	int luggage_count <- rnd(2);
	point final_target;
	int offsetx <- rnd(3);
	int offsety <- rnd(3);
	taxi_spot current_taxi;
	
	action go_to_taxi{
		if ((current_taxi = nil) or (current_taxi.state != "available")) {
			list<taxi_spot> available_taxi <- taxi_spot where (each.state = 'unavailable');
			if not empty(available_taxi) {
				current_taxi <- one_of(available_taxi);
				final_target <- current_taxi.location;
			}
		}
		if (final_target != nil) {
			do goto target: final_target on:network;
			if location distance_to final_target < 1 {
				ask taxi closest_to self{
					tourist_capacity <- tourist_capacity-1;
					has_passenger<-true;
				}
			people_left_terminal <- people_left_terminal+1;
			do die;
			}
		}
	}
	
	action go_to_exit{
		do goto target:point(one_of(exit)) on:network speed:speed;
	}

	state going_to_exit initial:true{
		do go_to_exit;
	transition to: going_to_taxi when: location distance_to point(one_of(exit))<=1;
	}
	
	state going_to_taxi {
		do go_to_taxi;
	}
	
	aspect default {
		draw circle(0.5) at:{location.x+offsetx,location.y+offsety} color: #white;
	}
	aspect glow{
		draw circle(3) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}


experiment "Steinwerder Simulation" type: gui {
	float minimum_cycle_duration <- 0.02;
	font regular <- font("Calibri", 12, # bold);
	parameter "Number of passengers" var: cruise_size init:2000 min:1 max:4500 category:"Amount of people";
	parameter "% of tourists using welcome center" init:80.0 var:terminal_arrival_choice min:1.0 max:100.0 category:"Behavioral profile";
	parameter "% of tourists arriving in HH by train" init:20.0 var:hamburg_arrival_choice min:1.0 max:100.0 category: "Behavioral profile";

	output {
		display charts  background: rgb(55,62,70) refresh:every(5#mn){
			chart "Tourists in the Terminal" type: pie size:{0.5,0.2} position: {0,0}background: rgb(55,62,70) axes: #white color: rgb(122,193,198) legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Passed Security" value: people_passed_security color: rgb(122,193,198);
				data "Checked-in" value: people_passed_checkin color: rgb(120,125,130);
				data "Collected card" value: people_collected_card color: rgb(179,186,196);
			}
			chart "Tourists in the Terminal" type: pie size:{0.5,0.2} position: {0.5,0}background: rgb(55,62,70) axes: #white color: rgb(122,193,198) legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Boarding" value: people_boarded_vessel color: rgb(122,193,198);
				data "Disembarking" value: people_left_terminal color: rgb(120,125,130);
			}
			chart " " type: series size:{1,0.3} position: {0,0.3} background: rgb(55,62,70) axes: #white color: #white legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Passed Security" value: people_passed_security color: rgb(179,186,196) marker_size:0 thickness:2;
				data "Checked-in" value: people_passed_checkin color: rgb(120,125,130) marker_size:0 thickness:2;
				data "Collected card" value: people_collected_card color: rgb(122,193,198) marker_size:0 thickness:2;
			}
			chart " " type: series size:{1,0.3} position: {0,0.6} background: rgb(55,62,70) axes: #white color: #white legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Boarding" value: nb_boarding color: rgb(179,186,196) marker_size:0 thickness:2;
				data "Disembarking" value: nb_disembarking color: rgb(122,193,198) marker_size:0 thickness:2;
				data "Current amount of people in terminal" value: (nb_disembarking+nb_boarding)  color:#white marker_size:0 thickness:2;
			}
		}
		display map type:opengl  background: rgb(30,40,49)
		{
			image site_plan transparency:0.75 refresh:false;
			
			species buildings aspect:default refresh:false;
			species tourist_arriving_car_taxi aspect: default;
			species tourist_taxi aspect: default;
			species tourist_shuttle aspect: default;
			species tourist_car aspect: default;
			species tourist_arriving_car_taxi aspect: glow transparency:0.85;
			species tourist_shuttle aspect: glow transparency:0.85;
			species tourist_taxi aspect: glow transparency:0.85;
			species tourist_car aspect: glow transparency:0.85;
			species tourist_arriving_generic aspect: default;
			species tourist_arriving_generic aspect: glow transparency:0.85;
			species crew_lug aspect: default;
			species crew_card aspect: default;
			species crew_security aspect: default;
			species crew_checkin aspect: default;
			species crew_lug_spot aspect:base;
			species card_stand aspect:base;
			species checkin_stand aspect:base;
			species security_stand aspect:base;
			species shuttle aspect: base;
			species car_arriving aspect:default;
			species car_leaving aspect:default;
			species taxi aspect:default;
			species taxi_arriving aspect:default;
			species shuttle_arriving aspect:default;
			//species pedestrian_path;

			overlay position: { 5, 5 } size: { 240 #px, 680 #px } background:rgb(55,62,70) transparency: 1.0 border: #black  {
                rgb text_color<-rgb(179,186,196);
                float y <- 12#px;
  				draw "Agents in the simulation" at: { 10#px, y } color: rgb(122,193,198) font: font("Calibri", 14, #plain) perspective:true;
                y <- y + 10 #px;
                draw circle(8#px) at: { 13#px, y +4#px } color: rgb(120,125,130);
                draw circle(2#px) at: { 13#px, y +4#px } color: #white;
                draw "CRUISE TOURIST" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
				y <- y + 14 #px;
                draw circle(2#px) at: { 13#px, y +4#px } color: rgb(179,186,196);
                draw "PEOPLE" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14#px;
                draw circle(3#px) at: { 13#px, y +4#px } color: rgb(72,123,143);
                draw "LUGGAGE DESK" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14#px;
                draw circle(6) at: { 13#px, y +4#px } color:rgb(179,186,196);
                draw "BUS SHUTTLE" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14 #px;
                draw "_____________________________"at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 15, #bold) perspective:true;
                y <- y + 21 #px;
				draw "Waiting time drop-off" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(avg_waiting_time/15, 8#px) at: { 0#px, y +4#px } color:rgb(179,186,196);
                y <- y + 14 #px;
                draw "Disembarking" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_disembarking*10, 8#px) at: { 0#px, y +4#px } color:rgb(122,193,198);
                y <- y + 14 #px;
                draw "Boarding" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_boarding*10, 8#px) at: { 0#px, y +4#px } color:rgb(120,125,130);
                y <- y + 14 #px;
                draw "Total Passengers in terminal" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle((nb_disembarking+nb_boarding)*5, 8#px) at: { 0#px, y +4#px } color:rgb(46,83,97);
                y <- y + 14 #px;
                draw "_____________________________"at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 15, #bold) perspective:true;
                y <- y + 21 #px; 
                draw time_info at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 21 #px; 
                draw "On board: "+ string(people_boarded_vessel) at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
           		 y <- y + 21 #px; 
                draw "Disembarked: "+ string(people_left_terminal) at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
           
            }
		}
	}
}
