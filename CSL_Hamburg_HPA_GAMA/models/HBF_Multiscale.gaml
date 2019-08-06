/***
* Name: HBF_Multiscale
* Author: JLopez from P. Taillandier's review on JLopez's model
* Description: simple model, that uses the moving skill - no accounting of people collision
***/

model HBF_Multiscale

global {
	string cityGISFolder <- "/external/hbf-model/";
	string Intervention <- "/external/hbf-model/Intervention/";
	string Scenario <- "/external/hbf-model/" among:["/external/hbf-model/","/external/hbf-model/Intervention-Plaza/"] parameter:"Scenario" category:"Infrastructure and service";
	string show_plan <- "/external/hbf-model/Intervention-Plaza/" among:["/external/hbf-model/","/external/hbf-model/Intervention-Plaza/"] parameter:"Show Intervention Plan" category:"Infrastructure and service";
	
	file shapefile_hbf <- file(cityGISFolder + "Hbf-Detail.shp");
	file shapefile_public_transportation <- file(cityGISFolder + "Detail_Public Transportation.shp");
	file shapefile_entry_points <- file(cityGISFolder + "Detail_Entry Points Platforms.shp");
	file pedestrian_paths <- file(cityGISFolder + "pedestrian_path_complex.shp");
	file boundary <- file(cityGISFolder + "Bounds.shp");
	file shapefile_moia <- file(cityGISFolder + "moia_spots.shp");
	file shapefile_taxi_stand <- file(Scenario + "taxi_stand.shp");
	file crew_spots <- file(Scenario + "crew_spots.shp");
	file sprinter_spots <- file(Scenario + "sprinter_spots.shp");
	file shapefile_shuttle <- file(Scenario + "Detail_Bus Shuttle.shp");
	file intervention_plan <- image_file(show_plan + "Intervention_modified.tif");
	
	file metro_lines <- file(cityGISFolder + "ambiance/Metro Lines.shp");
	file metro_origin <- file(cityGISFolder + "ambiance/Metro-origin.shp");
	file<geometry> road_traffic <- shape_file(cityGISFolder + "ambiance/Traffic.shp");
	file road_traffic_origin <- file(cityGISFolder + "ambiance/Traffic-origin.shp");
	file road_traffic_destination <- file(cityGISFolder + "ambiance/Traffic-destination.shp");
	file shapefile_buildingds <- file(cityGISFolder + "ambiance/buildings.shp");
	file shapefile_vessel <- file(cityGISFolder + "ambiance/Vessel.shp");
	
	file site_plan <- image_file(cityGISFolder + "Site Plan.tif");
	file shapefile_cruise_terminals <- file(Scenario + "larger_scale/Cruise_Terminals.shp");
	file shapefile_reference_hbf<- file(cityGISFolder + "larger_scale/reference_HBF.shp");
	file<geometry> path_to_terminals <- shape_file(cityGISFolder + "larger_scale/Connection to terminals.shp");
	
	csv_file telecom <- csv_file((cityGISFolder + "Teralytics_data.csv"),true);
	csv_file instagram <- csv_file((cityGISFolder + "Instagram_activeness.csv"),true);
	
	file ubahn_icon <- image_file(cityGISFolder + "/images/Ubahn.png");
	file sprinter_icon <- image_file(cityGISFolder + "/images/Sprinter.png");
	file shuttle_icon <- image_file(cityGISFolder + "/images/Shuttle.png");
	file tourist_icon <- image_file(cityGISFolder + "/images/tourist_boarding-01.png");
	file tourist_arriving_icon <- image_file(cityGISFolder + "/images/tourist_disembarking-01.png");
	file shuttle_tag <- image_file(cityGISFolder + "/images/shuttle_tag-01.png");
	file sprinter_tag <- image_file(cityGISFolder + "/images/sprinter_tag-01.png");
	file taxi_tag <- image_file(cityGISFolder + "/images/taxi_tag-01.png");
	file moia_tag <- image_file(cityGISFolder + "/images/moia_tag-01.png");
	file crew_tag <- image_file(cityGISFolder + "/images/crew_tag-01.png");
	
	geometry shape <- envelope(boundary);
	graph network;
	graph network_traffic;
	graph network_metro;
	graph terminal_flows;
	
	float step <- 5#s; //Simulation cycles equals to N seconds (speed of simulation)
	
	int nb_moia;
	int nb_sprinters;
	int people_in_station;
	int cruise_size;
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;

	int coming_train;
	float perception_distance; //Gehl social field of vision
	
	float train_freq;
	float shuttle_freq;
	int current_hour <- 8; //starting hour of the simulation
	int current_day <- 1; //starting day of the simulation
	int nb_tourist;
	int init_nb_tourist <- int(cruise_size*(hamburg_arrival_choice/100));
	int nb_people;
	float terminal_arrival_choice;
	float hamburg_arrival_choice;
	float moia_demand;
	string time_info;
	int people_in_terminal;
	int people_left_terminal;

	int nb_tourists update: length(tourist)+length(tourist_taxi)+length(tourist_shuttle)+length(tourist_moia);
	int nb_tourists_dropping_luggage update: tourist count each.dropping_now;
	int nb_tourists_to_drop_off update: tourist count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now);
	int nb_tourists_disoriented update: tourist count (not each.knows_where_to_go) + tourist_shuttle count (not each.knows_where_to_go) + tourist_taxi count (not each.knows_where_to_go) + tourist_moia count (not each.knows_where_to_go);
	int nb_tourists_to_shuttles update: tourist count each.dropped_luggage;
	int avg_waiting_time update: tourist sum_of(each.waiting_time_dropoff);

/////////AR development starts here
	reflex save when: every (10#sec){
		save tourist crs:3857 to: "../results/tourist-3857.csv" type:"csv" header:true rewrite:true;
	}
/////////AR development ends here	
/////////User interaction starts here
	list<shuttle_spot> moved_agents ;
	point target;
	geometry zone <- circle(20);
	bool can_drop;
/////////User interaction ends here
	
	reflex update when: every(5 #cycle) { 
		coming_train <- rnd(8); //trains arriving every hour to one platform 1 to 8.
		nb_tourists <- length(tourist)+length(tourist_taxi)+length(tourist_shuttle)+length(tourist_moia);	
		nb_tourists_dropping_luggage <- tourist count each.dropping_now;
		nb_tourists_to_drop_off <- tourist count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now);
		nb_tourists_disoriented <- tourist count (not each.knows_where_to_go) + tourist_shuttle count (not each.knows_where_to_go) + tourist_taxi count (not each.knows_where_to_go) + tourist_moia count (not each.knows_where_to_go);
		nb_tourists_to_shuttles <- tourist count each.dropped_luggage + tourist_shuttle count each.dropped_luggage;
		avg_waiting_time <- tourist sum_of(each.waiting_time_dropoff);
	} 
	
	reflex time_update when: every(1#hour) {
		current_hour <- current_hour +1;
		if current_hour > 20{
			current_hour <- 6;
			current_day <- current_day+1;
		}
		time_info <- "Day: " + string (current_day) + " Hour: " + string(current_hour) + ":00" ;
	}
	
	reflex time_peaks when: every(15#mn) { 
		create metro_train number:1 from:metro_origins;
		nb_tourist <- int((schedules sum_of each.tourists_create) / 3);
		nb_people <- int(people_in_station * (activeness sum_of each.people_create));
	}
	
/////////User interaction starts here
	action kill {
		ask moved_agents{
			do die;
		}
		moved_agents <- list<shuttle_spot>([]);
	}

	action duplicate {
		geometry available_space <- (zone at_location target) - (union(moved_agents) + 10);
		create shuttle_spot number: length(moved_agents) with: (location: any_location_in(available_space));
	}
	int count <- 0; //////////////////////double click modification test starts here
	float z <- 0.0;
	action click {
				if (count > 1 and machine_time - z > 200) {
			count <- 0;
			return;
		}
		if (count < 1) {
			count <- count + 1;
			z <- machine_time;
			return;
		}
		if(machine_time-z>200){ 
			z <- machine_time;
			return;
		} 
		count <- 0; //////////////////////double click modification test ends here
		if (empty(moved_agents)){
			list<shuttle_spot> selected_agents <- shuttle_spot inside (zone at_location #user_location);
			moved_agents <- selected_agents;
			ask selected_agents{
				difference <- #user_location - location;
			}
		} else if (can_drop){
			ask moved_agents{
			}
			moved_agents <- list<shuttle_spot>([]);
		}
	}

	action move {
		can_drop <- true;
		target <- #user_location;
		list<shuttle_spot> other_agents <- (shuttle_spot inside (zone at_location #user_location)) - moved_agents;
		geometry occupied <- geometry(other_agents);
		ask moved_agents{
			location <- #user_location - difference;
			if (occupied intersects self){
				can_drop <- false;
			} else{
			}
		}
	}
////////////User interaction ends here

	init{	
		create schedules from:telecom with:[arrival_hour:int(read("MainStationArrivalHour")), day:int(read("ShipID")), nb_tourist:int(read("Count"))];
		create activeness from:instagram with:[arrival_hour:int(read("MainStationArrivalHour")), percent_people:int(read("Percent"))];
		
		create vessel from:shapefile_vessel;
		create buildings from:shapefile_buildingds with:[height:int(read("Height"))];	
		create cruise_terminal from: shapefile_cruise_terminals with:[id:int(read("id"))];
		create hbf from: shapefile_hbf;
		create metro from: shapefile_public_transportation with: [station:string(read("station")), number:int(read("id"))];
		create crew_spot from:crew_spots;
		create sprinter_spot from: sprinter_spots;
		create shuttle_spot from: shapefile_shuttle;
		create moia_spot from: shapefile_moia;
		create entry_points from: shapefile_entry_points with: [platform_nb::int(read("platform"))]; //number of platform taken from shapefile
		create sprinter from: sprinter_spots {
			location <- point(one_of(vessel));
		}
		create shuttle from:shapefile_shuttle;
		create moia from:shapefile_moia number:nb_moia;
		create crew number: (nb_sprinters-1) from: crew_spots {
			spot <- one_of(crew_spot where (each.current_crew = nil));
			spot.current_crew <- self;
			location <- spot.location;
		}
		create metro_line from:metro_lines;
		network_metro <- as_edge_graph(metro_lines) with_optimizer_type "FloydWarshall";
		create pedestrian_path from:pedestrian_paths;
		network <- as_edge_graph(pedestrian_path) with_optimizer_type "FloydWarshall";	 
		create traffic_road from:road_traffic;
		network_traffic <- as_edge_graph(traffic_road) with_optimizer_type "FloydWarshall";	
		create terminal_flow from:path_to_terminals;
		terminal_flows <- as_edge_graph(terminal_flow) with_optimizer_type "FloydWarshall";	
		
		create traffic_origin from:road_traffic_origin;
		create traffic_destination from:road_traffic_destination;
		create metro_origins from:metro_origin;
		create taxi from:shapefile_taxi_stand;
		create taxi_spot from:shapefile_taxi_stand;
		create point_HBF from:shapefile_reference_hbf;
	}
}

species ref_shuttle  skills: [moving] control:fsm{
	point final_target;
	cruise_terminal current_terminal;
	int offset <- rnd(50);
	image_file tag <- shuttle_tag;
	action go{
		list<cruise_terminal> active_terminal <- cruise_terminal where (each.state = 'active');
		final_target <- point(one_of(active_terminal));
		do goto target: final_target on: terminal_flows speed:30#km/#h;
		if (location distance_to final_target) <= 10{
		do die;
		}
	}
	state going initial:true{
		do go;
	}
		aspect default {
		draw circle(10) at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
		draw circle(50) empty:true width:0.5 at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
		draw tag at:{location.x+offset,location.y+offset} size:1000;
	}
}
species ref_taxi skills: [moving] control:fsm{
	point final_target;
	cruise_terminal current_terminal;
	int offset <- rnd(50);
	image_file tag <- taxi_tag;
	action go{
		list<cruise_terminal> active_terminal <- cruise_terminal where (each.state = 'active');
		final_target <- point(one_of(active_terminal));
		do goto target: final_target on: terminal_flows speed:55#km/#h;
		if (location distance_to final_target) <= 10{
		do die;
		}
	}
	state going initial:true{
		do go;
	}
		aspect default {
		draw circle(15) at:{location.x+offset,location.y+offset} color:rgb(62,120,119);
		draw tag at:{location.x+offset,location.y+offset} size:1000;
	}
}
species ref_moia skills: [moving] control:fsm{
	point final_target;
	cruise_terminal current_terminal;
	int offset <- rnd(50);
	image_file tag <- moia_tag;
	action go{
		list<cruise_terminal> active_terminal <- cruise_terminal where (each.state = 'active');
		final_target <- point(one_of(active_terminal));
		do goto target: final_target on: terminal_flows speed:40#km/#h;
		if (location distance_to final_target) <= 10{
		do die;
		}
	}
	state going initial:true{
		do go;
	}
		aspect default {
		draw circle(15) at:{location.x+offset,location.y+offset} color:#yellow;
		draw tag at:{location.x+offset,location.y+offset} size:1000;
	}
}
species ref_sprinter skills: [moving] control:fsm{
	point final_target;
	cruise_terminal current_terminal;
	int offset <- rnd(50);
	image_file tag <- sprinter_tag;
	action go{
		list<cruise_terminal> active_terminal <- cruise_terminal where (each.state = 'active');
		final_target <- point(one_of(active_terminal));
		do goto target: final_target on: terminal_flows speed:50#km/#h;
		if (location distance_to final_target) <= 10{
		do die;
		}
	}
	state going initial:true{
		do go;
	}
		aspect default {
		draw circle(20) at:{location.x+offset,location.y+offset} color:rgb(179,186,196);
		draw tag at:{location.x+offset,location.y+offset} size:1000;
	}
}
species point_HBF control:fsm{
	action create_re_sprinter{
		create ref_sprinter number:rnd(1) with:[location::location];
	}
	action create_re_shuttle{
		create ref_shuttle number:rnd(1) with:[location::location];
	}
	action create_re_taxi{
		create ref_taxi number:rnd(1) with:[location::location];
	}
	action create_re_moia{
		create ref_moia number:rnd(1) with:[location::location];	
	}
}
species ref_taxi_return skills: [moving]{
	point final_target <- point(one_of(point_HBF));
	int offset <- rnd(50);
	image_file tag <- taxi_tag;
	reflex go{
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		ask one_of(taxi){
			do create_people;
		}
		do die;
	}
	aspect default {
		draw circle(15) at:{location.x+offset,location.y+offset} color:rgb(62,120,119);
		draw tag at:{location.x+offset,location.y+offset} size:1000;
	}
}
species ref_shuttle_return skills: [moving]{
	point final_target <- point(one_of(point_HBF));
	int offset <- rnd(50);
	image_file tag <- shuttle_tag;
	reflex go{
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		ask one_of(shuttle){
			do create_people;
		}
		do die;
	}
	aspect default {
		draw circle(10) at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
		draw circle(50) empty:true width:0.5 at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
		draw tag at:{location.x+offset,location.y+offset} size:1000;
	}
}
species ref_sprinter_return skills: [moving]{
	point final_target <- point(one_of(point_HBF));
	int offset <- rnd(50);
	image_file tag <- sprinter_tag;
	reflex go{
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}
	aspect default {
		draw circle(20) at:{location.x+offset,location.y+offset} color:rgb(179,186,196);
		draw tag at:{location.x+offset,location.y+offset} size:1000;
	}
}

species cruise_terminal control:fsm{
	int id;
	int active_terminal <- 1;
	int size;
	int freq_curve;
	
	reflex frequency_curve{
		if current_hour <= 6{
			freq_curve<-3600*24;
		}
		if current_hour = 7 {
			freq_curve<-15;
		}
		if current_hour = 8 {
			freq_curve<-10;
		}
		if current_hour = 9 {
			freq_curve<-5;
		}
		if current_hour = 10{
			freq_curve<-7;
		}
		if current_hour = 11{
			freq_curve<-12;
		}
		if current_hour>11 and current_hour<=18 {
			freq_curve<-15;
		}
		if current_hour>18{
			freq_curve<-3600*24;
		}
	}
	reflex disembarking_shuttle when: every(freq_curve#mn) {
		if self.state ="active" and init_nb_tourist>people_left_terminal and current_hour<15{
			create ref_shuttle_return number:1 with:[location::location];	
		}
	}
	reflex disembarking_taxi when: every(freq_curve+rnd(10)#mn) {
		if self.state ="active" and init_nb_tourist>people_left_terminal and current_hour<15{
			create ref_taxi_return number:1 with:[location::location];	
		}
	}
	reflex disembarking_sprinter when: every(freq_curve+rnd(10)#mn) {
		if self.state ="active" and init_nb_tourist>people_left_terminal{
			create ref_sprinter_return number:1 with:[location::location];	
		}
	}
	
	reflex active_terminals when: every(3600 #cycle){
		active_terminal <- active_terminal+1;
		if active_terminal > 3{
			active_terminal <- 1;
		}
	}
	state inactive initial:true {
		enter{
			size <-25;
			people_in_terminal<-0;
			people_left_terminal<-0;
		}
		transition to: active when: active_terminal = id;
	}
	state active{
		enter{
			size <-75;
		}
		transition to: inactive when: active_terminal !=id;
	}
	aspect base {
		draw circle(size) color:rgb(179,186,196);
		if self.state="active"{
			draw circle(size+people_in_terminal-people_left_terminal) empty:true width:0.5 color:rgb(179,186,196);
		}
	}
	aspect glow {
		draw circle(size*3) color: #white;
	}
}

species pedestrian_path {
	aspect default {
		draw shape color: #black;
	}
}
species vessel{}
species buildings{
	int height;
	aspect default {
		draw shape color: rgb(120,125,130) depth:(height*4);
	}
}
species car skills: [moving] control:fsm{
	point final_target <- point(one_of(traffic_destination));
	
	state going initial:true{
		do goto target: final_target on: network_traffic speed:rnd(10,29)#km/#h;
		if location distance_to final_target <= 10{
			do die;
		}
	}
		aspect default {
		draw rectangle(8,4) color: #grey rotate:heading;
	}
}
species moia_spot control:fsm{
	state unavailable {
		transition to: available when: location distance_to (moia closest_to self) >= 3;
	}
	state available initial:true{
		transition to:unavailable when: location distance_to (moia closest_to self) < 3;
	}	
	list<tourist_moia> waiting_tourists;
	aspect base {
		int i<-0;
		loop t over:waiting_tourists{
			//draw circle (1) at:{t.location.x+rnd(-3.0,3.0),t.location.y+rnd(-3.0,3.0)} color:#red ;	
			draw circle (1) at:{t.location.x+i,t.location.y+i*3} color:rgb(246,232,198) ;
			i<-i+1;	
		}	
	}
}
species taxi_spot control:fsm{
	state unavailable {
		transition to: available when: location distance_to (taxi closest_to self) >= 3;
	}
	state available initial:true{
		transition to:unavailable when: location distance_to (taxi closest_to self) < 3;
	}
	list<tourist_taxi> waiting_tourists;
	aspect base {
		int i<-0;
		loop t over:waiting_tourists{
			//draw circle (1) at:{t.location.x+rnd(-3.0,3.0),t.location.y+rnd(-3.0,3.0)} color:#red ;	
			draw circle (1) at:{t.location.x+i,t.location.y+i*3} color:rgb(246,232,198) ;
			i<-i+1;	
		}	
	}
}
species taxi skills:[moving] control:fsm {
	int luggage_capacity <- 8;
	int tourist_capacity <- 4;
	float speed <- 15 #km/#h;
	point target_loc <- point(one_of(vessel));
	taxi_spot own_spot;
	int people_create <- rnd(1,2);
	image_file tag <- taxi_tag;
	bool leaving;
	
	reflex depart_when_not_totally_full when: tourist_capacity <4 and every(5#mn) and state='loading'{ //time that people can wait inside a taxi until it departs (estimated 5min)
		leaving <- true;
	}
	
	action create_people {
		people_left_terminal <- people_left_terminal+people_create;
		create people number:people_create with:[location::location]{
				size<-1.5;
				color<- #white;
				glow<-8;
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl);
				icon <- tourist_arriving_icon;
		}	
	}
	action depart {
		do goto target: target_loc on: network_traffic speed:speed;
		if location distance_to point(one_of(vessel)) < 5{
			ask point_HBF {
				do create_re_taxi;	
			}
		}
	}
	state empty {
		enter {
			luggage_capacity <- 8;
			tourist_capacity <- 4;
			target_loc <- point(own_spot);
			leaving <- false;
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;
	}
	state loading initial:true {
		enter{
			own_spot <- taxi_spot closest_to self;
		}
		transition to: full when: tourist_capacity < 1 or luggage_capacity < 1 or leaving = true;
	}
	state full {
		enter {
			target_loc <- point(one_of(vessel));
		}
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}
	aspect base {
		draw rectangle(4,4) color:rgb(46,83,97);
		draw tag size:50;
	}
}
species moia skills:[moving] control:fsm {
	int luggage_capacity <- 10;
	int tourist_capacity <- 7;
	float speed <- 15 #km/#h;
	point target_loc <- point(one_of(vessel));
	moia_spot own_spot;
	int people_create <- rnd(2,5);
	image_file tag <- moia_tag;
	bool leaving;
	
	reflex depart_when_not_totally_full when: tourist_capacity <7 and every(5#mn) and state='loading'{ //time that people can wait inside a moia shuttle until it departs (estimated 5min)
		leaving <- true;
	}
	
	action create_people {
		people_left_terminal <- people_left_terminal+people_create;
		create people number:people_create with:[location::location]{
				size<-1.5;
				color<- #white;
				glow<-8;
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl);
				icon <- tourist_arriving_icon;
		}	
	}
	action depart {
		do goto target: target_loc on: network_traffic speed:speed;
		if location distance_to point(one_of(vessel)) < 5{
			ask point_HBF {
				do create_re_moia;	
			}
		}
	}
	state empty {
		enter {
			luggage_capacity <- 10;
			tourist_capacity <- 7;
			target_loc <- point(own_spot);
			leaving <- false;
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;
	}
	state loading initial:true {
		enter{
			own_spot <- moia_spot closest_to self;
		}
		transition to: full when: tourist_capacity < 1 or luggage_capacity < 1 or leaving = true;
	}
	state full {
		enter {
			target_loc <- point(one_of(vessel));
		}
		do depart;
		transition to: empty when: (location distance_to point(one_of(vessel)) <5);
	}

	aspect base {
		draw rectangle(5,3) color:#yellow  rotate:heading;
		draw tag size:50;
	}
}

species metro_train skills: [moving] control:fsm{
	point final_target <- point(one_of(metro_origins));
		
	state going initial:true{
		do goto target:final_target on: network_metro speed:15#km/#h;
		if (location distance_to final_target) <= 10{
			do die;
		}
	}
	aspect default {
		draw rectangle(150,10) color:rgb(68,79,88) rotate:heading;
	}
}

species traffic_origin{
	reflex create_cars when: every(40#cycle){
		create car number: rnd(1) with: [location::location];
	}
}

species metro_origins{}
species schedules {
	int nb_tourist;
	int arrival_hour;
	int day;
	int tourists_create;
	
	reflex tourist_number when: every(15#mn){
		tourists_create<-0;
		if current_hour = arrival_hour and current_day =  day{
			tourists_create <- nb_tourist;
		}
	}
}
species activeness {
	int percent_people;
	int arrival_hour;
	int people_create;
	
	reflex tourist_number when: every(15#mn){
		people_create <- 0;
		if current_hour = arrival_hour{
			people_create <- percent_people;
		}
	}
}


species traffic_destination{}
species traffic_road{} 
species terminal_flow{}
species metro_line{}
species crew_spot{
	crew current_crew;
	list<tourist> waiting_tourists;
	aspect base {
		int i<-0;
		loop t over:waiting_tourists{
			//draw circle (1) at:{t.location.x+rnd(-3.0,3.0),t.location.y+rnd(-3.0,3.0)} color:#red ;	
			draw circle (1) at:{t.location.x+i,t.location.y+i*3} color:rgb(246,232,198) ;
			i<-i+1;	
		}
	} 
}

species sprinter_spot control:fsm{
	state unavailable {
		transition to: available when: location distance_to (sprinter closest_to self) >= 1;
	}
	state available initial:true{
		transition to:unavailable when: location distance_to (sprinter closest_to self) < 1;
	}
	aspect default {
		draw circle(5.0) color: #cyan;
	}
}

species hbf{
	aspect base {
		draw shape border:rgb(75,77,79) width:0.5 empty:true;
	}
}

species metro{
	image_file icon <- ubahn_icon;
	string station;
	int number;
			
	reflex create_opeople when: every(75 #cycle){
		create people number: rnd(1) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(one_of(metro));
				size<-0.5;
				color<- rgb(179,186,196);
			}
		create people number: rnd(1) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(any_location_in(geometry(walking_area)));
				size<-0.5;
				color<- rgb(179,186,196);
			}	
		} 
	aspect base {
		draw icon size:2 rotate:180;
		draw station font:font("Calibri",3, #plain) color:#gray anchor:#center;
	}
}

species shuttle_spot control:fsm {
	crew current_crew;
	rgb color <- #blue;	

	state unavailable {
		transition to: available when: location distance_to (shuttle closest_to self) >= 1;
	}
		state available initial:true{
		transition to:unavailable when: location distance_to (shuttle closest_to self) < 1;
	}
	
	list<tourist_shuttle> waiting_tourists;
	aspect base {
		int i<-0;
		loop t over:waiting_tourists{
			//draw circle (1) at:{t.location.x+rnd(-3.0,3.0),t.location.y+rnd(-3.0,3.0)} color:#red ;	
			draw circle (1) at:{t.location.x+i,t.location.y+i*3} color:rgb(246,232,198) ;
			i<-i+1;	
		}
	} 	
		
////////////User interaction starts here
	point difference <- { 0, 0 };
	reflex r {
		if (!(moved_agents contains self)){}
	}
////////////User interaction ends here
	aspect default {
		draw circle(8) color:rgb(179,186,196);
		}
}

species shuttle skills:[moving] control:fsm {
	rgb color <- #blue;	
	image_file icon <- shuttle_icon;
	image_file tag <- shuttle_tag;
	int luggage_capacity <- 100;
	int tourist_capacity <- 50;
	float speed <- 10 #km/#h;
	point target_loc <- point(one_of(vessel));
	bool is_scheduled;
	shuttle_spot own_spot;
	int people_create <- rnd(5,10);
	
	action create_people {
		people_left_terminal <- people_left_terminal+people_create;
		create people number:people_create with:[location::location]{
				size<-1.5;
				color<- #white;
				glow<-8;
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl);
				icon <- tourist_arriving_icon;
		}	
	}	
	action depart {
		do goto target: target_loc on:network_traffic speed:speed;
		if location distance_to point(one_of(vessel)) < 10{
			ask point_HBF {
				do create_re_shuttle;	
			}
		}
	}	
	reflex scheduled_depart when: every(1/shuttle_freq#h) {
		is_scheduled <- true;
	}	
	state empty {
		enter {
			is_scheduled <- false;
			luggage_capacity <- 100;
			tourist_capacity <- 50;
			own_spot <- one_of(shuttle_spot where(each.state='available'));
			if own_spot = nil{
				own_spot <- one_of(shuttle_spot);
			} 
			target_loc <- point(own_spot);
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;
	}	
	state loading initial:true {
		enter{
			own_spot <- shuttle_spot closest_to self;
		}
		transition to: full when: tourist_capacity < 1 or luggage_capacity < 1 or is_scheduled;
	}	
	state full {
		enter {
			target_loc <- point(one_of(vessel));
		}
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}

	aspect base {
		draw icon size:40 rotate: my heading;
		draw tag size:50;
	}
}

species entry_points{
	int platform_nb;
	
	reflex train_comes when: every((1/train_freq)#hour){
		if (coming_train = platform_nb) {	
			create people number: nb_people*0.01/train_freq with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(one_of(metro));
				size<-0.5;
				color<- rgb(179,186,196);
			}
			create tourist number: ((nb_tourist/train_freq)*(terminal_arrival_choice/100)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			}	
			create tourist_shuttle number: ((nb_tourist/train_freq*2)*(1-terminal_arrival_choice/100)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			}
			create tourist_taxi number: (nb_tourist/train_freq*2)*(1-terminal_arrival_choice/100)*(1-moia_demand/100) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;	
			}
			create tourist_moia number: (nb_tourist/train_freq*2)*(1-terminal_arrival_choice/100)*(moia_demand/100) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;	
			}
		}
	}		
	aspect base {
		draw square(2);
	}
}

species walking_area{}

species people skills: [moving,network] control:fsm {
	point final_target;
	float size; 
	float speed <-gauss(3,2) #km/#h min: 1.0;
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	rgb color;
	int glow;
	image_file icon;
////////// AR development starts here
	reflex move {
		do send to:"csl/hafen" contents:[name, location];
		do goto target: final_target on: network speed:speed;
	}
////////// AR development ends here	
	state dead{
		do die;
	}
	state walking initial:true {
		if final_target = nil {
			final_target <- any_location_in(geometry(network));
		}
		
		do goto target: final_target on:network speed:speed;
		transition to: dead when:location distance_to final_target <= 15;
	}	
	
	aspect default {
		draw circle(size) at:{location.x+offsetx,location.y+offsety} color:color;
		draw icon at:{location.x+offsetx,location.y+offsety} size:50 rotate:0;		
	}
	aspect glow{
		draw circle(glow) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species sprinter skills:[moving] control:fsm {
	point target_loc;
	int luggage_capacity;
	image_file icon <- sprinter_icon;
	image_file tag <- sprinter_tag;
	float speed <- 10 #km/#h;
 
	action depart {
		do goto target: target_loc on:network_traffic speed:speed;
		if location distance_to point(one_of(vessel)) < 5{
			ask point_HBF {
				do create_re_sprinter;	
			}
		}
	}
	
	state empty initial:true {
		enter {
			luggage_capacity <- 50;
			target_loc <- point(one_of(sprinter_spot where (each.state = 'available')));
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;		
	}	
	state loading{
		transition to: full when: luggage_capacity < 1;
	}	
	state full {
		enter {
			target_loc <- point(one_of(vessel));
		}
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}	
	aspect default {
		draw circle(6) color: rgb(72,123,143);
		draw icon size:7 rotate: my heading ;
		draw tag size:50;
	}
}

species crew skills:[moving] control:fsm {
	point target_loc;
	crew_spot spot;
	int carrying_luggage;
	tourist current_tourist;
	sprinter current_sprinter;
	rgb color <- #green;
	image_file tag <- crew_tag;

	action carry_luggage{
		if ((current_sprinter = nil) or (current_sprinter.state != "loading")) {
			list<sprinter> available_sprinter <- sprinter where (each.state = 'loading');
			if not empty(available_sprinter) {
				current_sprinter <- available_sprinter closest_to self;
				target_loc <- current_sprinter.location;
			}
		}		
		if (target_loc != nil) {
			do goto target: target_loc;
			if location distance_to target_loc < 1 {
				current_sprinter.luggage_capacity <- current_sprinter.luggage_capacity - carrying_luggage;
				carrying_luggage <- 0;
				current_sprinter <- nil;
				target_loc <- nil;
			}
		}
	}
	
	state go_back_spot {
		enter {
			color <- #yellow;
		}
		do goto target:spot;
		transition to: available  when: location = spot.location;
	}	
	state go_to_sprinter {
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
			color <- #green;
		}
		transition to: go_to_sprinter when: not empty(spot.waiting_tourists);
	}
	aspect default {
		draw circle(1) color:color;
		draw tag size:50;
	}
}
species tourist skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	bool dropped_luggage;
	int luggage_count <- rnd(1)+1;
	bool dropping_now <- false;
	int tourist_line;
	crew_spot the_spot;
	list<crew_spot> known_drop_off_areas;
	point final_target;
	bool knows_where_to_go <- false;
	shuttle current_shuttle;
	int start_waiting_time_dropoff;
	int end_waiting_time_dropoff;
	int waiting_time_dropoff;
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	image_file icon <- tourist_icon;
	int size <-5;
	point previous_location <- self.location;
	
	reflex waiting_time when: every(20#cycle) and knows_where_to_go{
		waiting_time_dropoff<-end_waiting_time_dropoff-start_waiting_time_dropoff;
		if waiting_time_dropoff < 0 {
			waiting_time_dropoff<-0;
		}
	}	
	reflex update_location_1 when: every(17#mn) and not knows_where_to_go{
		previous_location <- self.location;
	}
	reflex update_location_2 when: every(37#mn) and not knows_where_to_go{ //this part solves agents stuck by geometry simplification of shp pedestrian path
		if self distance_to previous_location = 0{
			final_target <- any_location_in(geometry(network));
		}
	}
	state search_drop_off_luggage initial: true{
		if (final_target = nil) or self distance_to one_of(entry_points) < 1 {
			final_target <- any_location_in(geometry(network));
		}
		do goto target: final_target on: network speed:speed;
		if (self distance_to final_target < 5.0) {
			final_target <- nil;
		}
		known_drop_off_areas <- known_drop_off_areas + (crew_spot at_distance perception_distance) where (each.current_crew != nil);
		transition to: goto_drop_off_luggage when: not empty(known_drop_off_areas);
	}	
	state goto_drop_off_luggage {
		enter {
			the_spot <- crew_spot(known_drop_off_areas max_of length(each.waiting_tourists)); 
			if the_spot = nil {the_spot <- one_of(known_drop_off_areas);}
			final_target <- the_spot.location;
			knows_where_to_go <- true;
		}
		do goto target: final_target on: network speed:speed;
		transition to: drop_off_luggage when: (self distance_to final_target) < 10.0;
	}	
	state drop_off_luggage {
		enter {
			start_waiting_time_dropoff <- cycle;
			if the_spot.waiting_tourists contains self{} else {the_spot.waiting_tourists << self;}
			size<-0;
			dropping_now <- true;
		}
		transition to: go_to_the_bus when: dropped_luggage;
	}
	state go_to_the_bus {
		enter {
			end_waiting_time_dropoff <- cycle;
			dropping_now <- false;
			final_target <- point(one_of(shuttle_spot));
			size <- 5;
		}
		do goto target: final_target on: network speed:speed;
		if (location distance_to final_target) < 10.0  {
			current_shuttle <- shuttle closest_to self;	
			current_shuttle.tourist_capacity <- current_shuttle.tourist_capacity - 1;
			people_in_terminal <-people_in_terminal+1;
			do die;
		}
	}	
	aspect default {
		draw circle(size*0.2) at:{location.x+offsetx,location.y+offsety} color: #white;
		draw icon at:{location.x+offsetx,location.y+offsety} size:50 rotate:0;
	}
	aspect glow{
		draw circle(size) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species tourist_shuttle skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	bool dropped_luggage;
	int luggage_count <- 2;
	bool dropping_now <- false;
	int tourist_line;
	shuttle_spot the_spot;
	list<shuttle_spot> known_boarding_areas;
	point final_target;
	bool knows_where_to_go <- false;
	shuttle current_shuttle;
	int offsetx <- rnd(7);
	int offsety <- rnd(7);
	image_file icon <- tourist_icon;
	int size <-5;
	list<shuttle> available_shuttles;
	bool is_waiting;
	
	state search_drop_off_luggage initial: true{
		if (final_target = nil) {
			final_target <- any_location_in(geometry(network));
		}
		do goto target: final_target on: network speed:speed;
		if (self distance_to final_target < 5.0) {
			final_target <- nil;
		}
		known_boarding_areas <- known_boarding_areas + (shuttle_spot at_distance (perception_distance*2));
		transition to: goto_drop_off_luggage when: not empty(known_boarding_areas);
	}	
	state goto_drop_off_luggage {
		enter {
			the_spot <- one_of(known_boarding_areas); 
			final_target <- the_spot.location;
			knows_where_to_go <- true;
		}
		do goto target: final_target on: network speed:speed;
		transition to: board_the_bus when: (self distance_to final_target) < 2.0;
	}	
	reflex list_shuttle{
		available_shuttles <- shuttle where (each.state = 'loading');
	}	
	state board_the_bus {
		if (self distance_to final_target) < 2.0{
			current_shuttle <- available_shuttles closest_to self;	
			if current_shuttle != nil{
				if current_shuttle.tourist_capacity > 0{
					current_shuttle.tourist_capacity <- current_shuttle.tourist_capacity-1;
					current_shuttle.luggage_capacity <- current_shuttle.luggage_capacity - self.luggage_count;
					people_in_terminal <-people_in_terminal+1;
					do die;
				}
			}else{
				is_waiting <- true;
				if self in the_spot.waiting_tourists { 
					}else{
					the_spot.waiting_tourists << self;
				} 
			}		
		}
	}
	
	aspect default {
		draw circle(1.5) at:{location.x+offsetx,location.y+offsety} color: #white;
		draw icon at:{location.x+offsetx,location.y+offsety} size:50 rotate:0;
	}
	aspect glow{
		draw circle(8) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species tourist_taxi skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	int luggage_count <- rnd(1,4);
	taxi_spot the_spot;
	list<taxi_spot> known_boarding_areas;
	point final_target;
	bool knows_where_to_go <- false;
	taxi current_taxi;
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	image_file icon <- tourist_icon;
	int size <-5;
	list<taxi> available_taxis;
	bool is_waiting;
	
	state search_drop_off_luggage initial: true{
		if (final_target = nil) {
			final_target <- any_location_in(geometry(network));
		}
		do goto target: final_target on: network speed:speed;
		if (self distance_to final_target < 5.0) {
			final_target <- nil;
		}
		known_boarding_areas <- known_boarding_areas + (taxi_spot at_distance (perception_distance*2));
		transition to: goto_drop_off_luggage when: not empty(known_boarding_areas);
	}	
	state goto_drop_off_luggage {
		enter {
			the_spot <- one_of(known_boarding_areas); 
			final_target <- the_spot.location;
			knows_where_to_go <- true;
		}
		do goto target: final_target on: network speed:speed;
		transition to: board_taxi when: (self distance_to final_target) < 2.0;
	}	
	reflex list_taxi{
		available_taxis <- taxi where (each.state = 'loading');
	}
	
	state board_taxi {
		if (self distance_to final_target) < 2.0{
			current_taxi <- available_taxis closest_to self;	
			if current_taxi != nil{
				if current_taxi.tourist_capacity > 0{
					current_taxi.tourist_capacity <- current_taxi.tourist_capacity-1;
					current_taxi.luggage_capacity <- current_taxi.luggage_capacity - self.luggage_count;
					people_in_terminal <-people_in_terminal+1;
					do die;
				}
			}else{
				is_waiting <- true;
				if self in the_spot.waiting_tourists { 
					}else{
					the_spot.waiting_tourists << self;
				}
			}		
		}
	}	
	aspect default {
		draw circle(1.5) at:{location.x+offsetx,location.y+offsety} color: #white;
		draw icon at:{location.x+offsetx,location.y+offsety} size:50 rotate:0;
	}
	aspect glow{
		draw circle(8) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}
species tourist_moia skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	int luggage_count <- 2;
	moia_spot the_spot;
	list<moia_spot> known_boarding_areas;
	point final_target;
	bool knows_where_to_go <- false;
	moia current_moia;
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	image_file icon <- tourist_icon;
	int size <-5;
	list<moia> available_moias;
	bool is_waiting;
	
	state search_drop_off_luggage initial: true{
		if (final_target = nil) {
			final_target <- any_location_in(geometry(network));
		}
		do goto target: final_target on: network speed:speed;
		if (self distance_to final_target < 5.0) {
			final_target <- nil;
		}
		known_boarding_areas <- known_boarding_areas + (moia_spot at_distance (perception_distance*2));
		transition to: goto_drop_off_luggage when: not empty(known_boarding_areas);
	}	
	state goto_drop_off_luggage {
		enter {
			the_spot <- one_of(known_boarding_areas); 
			final_target <- the_spot.location;
			knows_where_to_go <- true;
		}
		do goto target: final_target on: network speed:speed;
		transition to: board_taxi when: (self distance_to final_target) < 2.0;
	}	
	reflex list_moia{
		available_moias <- moia where (each.state = 'loading');
	}	
	state board_taxi {
		if (self distance_to final_target) < 2.0{
			current_moia <- available_moias closest_to self;	
			if current_moia != nil{
				if current_moia.tourist_capacity > 0{
					current_moia.tourist_capacity <- current_moia.tourist_capacity-1;
					current_moia.luggage_capacity <- current_moia.luggage_capacity - self.luggage_count;
					people_in_terminal <-people_in_terminal+1;
					do die;
				}
			}else{
				is_waiting <- true;
				if self in the_spot.waiting_tourists { 
					}else{
					the_spot.waiting_tourists << self;
				}
			}		
		}
	}
	
	aspect default {
		draw circle(1.5) at:{location.x+offsetx,location.y+offsety} color: #white;
		draw icon at:{location.x+offsetx,location.y+offsety} size:50 rotate:0;
	}
	aspect glow{
		draw circle(8) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

experiment "Port City Model" type: gui {
	float minimum_cycle_duration <- 0.02;
	font regular <- font("Calibri", 12, # bold);
	parameter "Number of passengers" var: cruise_size init:2000 min:1 max:4500 category:"Amount of people";
	parameter "People in the station" var: people_in_station init:2000 min:1 max: 10000 category: "Amount of people";
	parameter "Frequency of trains (Fractions of an hour)" var: train_freq init:4.0 min:0.1 max:12.0 category: "Amount of people";
	parameter "Frequency of bus shuttles (Fractions of an hour)" var:shuttle_freq init:2.0 min:0.1 max:12.0 category: "Infrastructure and service";
	parameter "Size of welcome center" var: nb_sprinters init:3 min:1 max: 5 category: "Infrastructure and service";
	parameter "Number of Moia vehicles" var:nb_moia init:1 min:1 max:6 category: "Infrastructure and service";
	parameter "Perception of info" var: perception_distance init:250.0 min:1.0 max:10000.0 category: "Infrastructure and service";
	parameter "% of tourists using welcome center" init:80.0 var:terminal_arrival_choice min:1.0 max:100.0 category:"Behavioral profile";
	parameter "% of tourists arriving in HH by train" init:20.0 var:hamburg_arrival_choice min:1.0 max:100.0 category: "Behavioral profile";
	parameter "% MOIA vs taxi demand" init:30.0 var:moia_demand min:1.0 max:99.0 category: "Behavioral profile";

	output {
		display charts  background: rgb(55,62,70) refresh:every(5#mn) camera_interaction:false{
			chart "Tourist using welcome center" type: pie size:{0.5,0.2} position: {0,0}background: rgb(55,62,70) axes: #white color: rgb(122,193,198) legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Disoriented" value: nb_tourists_disoriented color: rgb(122,193,198);
				data "To the welcome center" value: nb_tourists_to_drop_off color: rgb(120,125,130);
				data "Dropping off their luggage" value: nb_tourists_dropping_luggage color: rgb(179,186,196);
				data "To the shuttles" value: nb_tourists_to_shuttles color: rgb(200,200,200);
			}
			chart "Tourist in Terminal" type: pie size:{0.5,0.2} position: {0.5,0}background: rgb(55,62,70) axes: #white color: rgb(122,193,198) legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Boarding" value: people_in_terminal color: rgb(122,193,198);
				data "Disembarking" value: people_left_terminal color: rgb(120,125,130);
			}
			chart " " type: series size:{1,0.3} position: {0,0.3} background: rgb(55,62,70) axes: #white color: #white legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Disoriented tourists" value: nb_tourists_disoriented color: rgb(179,186,196) marker_size:0 thickness:1.5;
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: rgb(120,125,130) marker_size:0 thickness:1.5;
				data "Tourists: welcome center" value: length(tourist) color: rgb(179,186,196) marker_size:0 thickness:2;
			}
			chart " " type: series size:{1,0.3} position: {0,0.6} background: rgb(55,62,70) axes: #white color: #white legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Tourists: welcome center" value: length(tourist) color: rgb(179,186,196) marker_size:0 thickness:1.5;
				data "Tourists: Taxi" value: length(tourist_taxi) color: rgb(122,193,198) marker_size:0 thickness:1.5;
				data "Tourists: Shuttle" value: length(tourist_shuttle) color: rgb(120,125,130) marker_size:0 thickness:1.5;
				data "Tourists: Moia" value: length(tourist_moia) color: #yellow marker_size:0 thickness:1.5;
				data "Total Tourists" value: length(tourist)+length(tourist_taxi)+length(tourist_shuttle)+length(tourist_moia) color: #white marker_size:0 thickness:2;
			}
		}
		display map type:opengl  background: rgb(30,40,49) camera_interaction:true
		{
			image site_plan transparency:0.75;
			image intervention_plan position:{500,300};	
			
			//species buildings aspect:default transparency:0.9;
			species hbf aspect:base refresh:false;
			species metro aspect: base refresh:false;
			species people aspect: default; species people aspect: glow transparency:0.95;
			species tourist aspect: default; species tourist aspect: glow transparency:0.85;
			species tourist_taxi aspect: default; species tourist_taxi aspect: glow transparency:0.85;
			species tourist_moia aspect: default; species tourist_moia aspect: glow transparency:0.85;
			species tourist_shuttle aspect: default; species tourist_shuttle aspect: glow transparency:0.85;
			species sprinter aspect: default;
			species crew aspect: default;
			species crew_spot aspect:base ;
			species cruise_terminal aspect:base; species cruise_terminal aspect: glow transparency:0.85;
			species car aspect:default;
			species taxi aspect:base;
			species moia aspect:base;
			species metro_train aspect:default transparency:0.5;
			species ref_shuttle aspect:default;
			species ref_taxi aspect:default;
			species ref_moia aspect:default;
			species ref_sprinter aspect:default;
			species ref_shuttle_return aspect:default;
			species ref_taxi_return aspect:default;
			species ref_sprinter_return aspect:default;
			species moia_spot aspect:base;
			species taxi_spot aspect:base;
			species shuttle_spot aspect: base; species shuttle_spot aspect: default;
			species shuttle aspect: base;		
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
                draw "LUGGAGE SPRINTER" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14#px;
                draw circle(6) at: { 13#px, y +4#px } color:rgb(179,186,196);
                draw "BUS SHUTTLE [INTERACTION]" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14 #px;
                draw "_____________________________"at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 15, #bold) perspective:true;
                y <- y + 21 #px;
				draw "Waiting time at welcome center" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(avg_waiting_time/15, 8#px) at: { 0#px, y +4#px } color:rgb(179,186,196);
                y <- y + 14 #px;
                draw "Drop-off line length" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_dropping_luggage*10, 8#px) at: { 0#px, y +4#px } color:rgb(122,193,198);
                y <- y + 14 #px;
                draw "Expected people arriving to welcome center" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_to_drop_off*10, 8#px) at: { 0#px, y +4#px } color:rgb(120,125,130);
                y <- y + 14 #px;
                draw "Disoriented" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_disoriented*10, 8#px) at: { 0#px, y +4#px } color:rgb(62,120,119);
                y <- y + 14 #px;
                draw "On the way to bus shuttle" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_to_shuttles*10, 8#px) at: { 0#px, y +4#px } color:rgb(46,83,97);
                y <- y + 14 #px;
                draw "_____________________________"at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 15, #bold) perspective:true;
                y <- y + 21 #px; 
                draw time_info at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 21 #px; 
                draw "People to the terminal: "+ string(people_in_terminal) at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
           		 y <- y + 21 #px; 
                draw "People from the terminal: "+ string(people_left_terminal) at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;           
            }
			
////////////////////User interaction starts here		
			event mouse_move action: move;
			event mouse_up action: click;
			event 'r' action: kill;
			event 'c' action: duplicate;
			graphics "Full target" {
				int size <- length(moved_agents);
				if (size > 0){
					rgb c1 <- rgb(62,120,119);
					rgb c2 <- rgb(62,120,119);
					draw zone at: target empty: false border: false color: (can_drop ? c1 : c2);
					draw string(size) at: target + { -15, -15 } font: font("Calibri", 8, #plain) color: rgb(179,186,196);
					draw "'r': remove" at: target + { -15, 0 } font: font("Calibri", 8, #plain) color: rgb(179,186,196);
					draw "'c': copy" at: target + { -15, 15 } font: font("Calibri", 8, #plain) color: rgb(179,186,196);
				}
			}
////////////////////User interaction ends here	
		}
	}
}
