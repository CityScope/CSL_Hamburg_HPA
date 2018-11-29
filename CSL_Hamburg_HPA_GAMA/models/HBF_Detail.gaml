/***
* Name: HBFDetail
* Author: JLopez
* Description: The model aims to represent the movement of people and tourists in the tran station and surounding area. People arrive by train and go to random destinations. Tourist arrive by train and go to (1) taxi (2) luggage dropoff area and (3) take bus shuttle.
* Update 28Nov2018: User interaction allows to move the final destinations (bus shuttle spots) on the run
* Tags: Tag1, Tag2, TagN
***/

model HBFDetail

global {
	string cityGISFolder <- "./../external/";
	file shapefile_hbf <- file(cityGISFolder + "Hbf-Detail.shp");
	file shapefile_walking_paths <- file(cityGISFolder + "Detail_Walking Areas.shp");
	file shapefile_public_transportation <- file(cityGISFolder + "Detail_Public Transportation.shp");
	file shapefile_dropoff_area <- file(cityGISFolder + "Dropoffarea.shp");
	file shapefile_shuttle <- file(cityGISFolder + "Detail_Bus Shuttle.shp");
	file shapefile_entry_points <- file(cityGISFolder + "Detail_Entry Points Platforms.shp");
	file shapefile_roads <- file(cityGISFolder + "Detail_Road.shp");
	
	file tourist_icon <- image_file(cityGISFolder + "/images/Tourist.gif");
	file person_icon <- image_file(cityGISFolder + "/images/Person.gif");
	file ubahn_icon <- image_file(cityGISFolder + "/images/Ubahn.png");
	file sprinter_icon <- image_file(cityGISFolder + "/images/Sprinter.png");
	file shuttle_icon <- image_file(cityGISFolder + "/images/Shuttle.png");
	
	geometry shape <- envelope(shapefile_walking_paths);
	graph the_graph;
	float step <- 1#s;
	int current_hour update: (time / #hour) mod 24;
	
	int nb_taxis <- 20;
	int nb_shuttle <- 2;
	int nb_sprinters <- 3 parameter: true;
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int maximal_turn <- 30; //in degree
	int cohesion_factor_ppl <- 1; //must be more than 0
	int cohesion_factor_tou <- 100;
	float people_size <- 1.0;
	int coming_train;
	int nb_people_existing;
	int nb_tourist_disoriented;
	int nb_tourist_to_shuttles;
	float perception_distance <- 600.0 parameter: true;
	int precision <- 120 parameter: true;

/////////User interaction starts here
	list<shuttle_spot> moved_agents ;
	point target;
	geometry zone <- circle(10);
	bool can_drop;
	
/////////User interaction ends here
	
	reflex update { 
		coming_train <- rnd(500)+rnd(700); //trains arriving randomly when the sum of these numbers is 1-8.
		nb_people_existing <- length(list(people));
		nb_tourist_disoriented <- int(tourist count(each.knows_where_to_go =  false));
		nb_tourist_to_shuttles <- int(tourist count(each.knows_where_to_go));
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

	action click {
		if (empty(moved_agents)){
			list<shuttle_spot> selected_agents <- shuttle_spot inside (zone at_location #user_location);
			moved_agents <- selected_agents;
			ask selected_agents{
				difference <- #user_location - location;
				color <- # olive;
			}
		} else if (can_drop){
			ask moved_agents{
				color <- # red;
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
				color <- # red;
				can_drop <- false;
			} else{
				color <- # olive;
			}
		}
	}
////////////User interaction ends here

	init{			
		create hbf from: shapefile_hbf;
		create metro from: shapefile_public_transportation;
		create roads from: shapefile_roads;
		the_graph <- as_edge_graph(list(roads));
		
		create dropoff_area from: shapefile_dropoff_area;
		create shuttle_spot from: shapefile_shuttle;
		create entry_points from: shapefile_entry_points with: [platform_nb::int(read("platform_s"))]; //number of platform taken from shapefile
		create walking_area from: shapefile_walking_paths {
			//Creation of the free space by removing the shape of the buildings (train station complex)
			free_space <- geometry(walking_area);
		}
		free_space <- free_space simplification(1.0);
		create sprinter number:nb_sprinters {
			location <- any_location_in(one_of(roads));
		}
	}
}
species roads{}

species hbf{
	rgb color <- #gray;	
	aspect base {
		draw shape color: color;
	}
}

species metro{
		image_file icon <- ubahn_icon;
	aspect base {
		draw icon size:8;
	}
}

species dropoff_area control: fsm{
	rgb color <- #white;
	bool has_sprinter;
	list<tourist> tou_inside;
	list<sprinter> sp_inside;
	
	reflex update_lists{
		tou_inside <- tourist inside (self);
		sp_inside <- sprinter inside (self);
	}
	
	reflex with_sprinter {
		if length(sp_inside) > 0{
			has_sprinter<-true;
		}
	}
	
	state empty initial:true {
		transition to: with_tourist when: length(tou_inside) > 1;
	}
	
	state with_tourist {
		transition to: empty when: length(tou_inside) < 2;
	}
	
	aspect base {
		draw shape;
	}
}

species shuttle_spot{
	rgb color <- #blue;	
	image_file icon <- shuttle_icon;
	
////////////User interaction starts here
	point difference <- { 0, 0 };
	reflex r {
		if (!(moved_agents contains self)){}
	}
////////////User interaction ends here
	aspect base {
		draw icon size:40 rotate:30;
	}
}

species entry_points{
	bool has_train <- false;
	int platform_nb;
	
	reflex train {
		if (coming_train = platform_nb) {
			has_train <- true;
			
			create species(people) number: rnd(15){
			speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			target_loc <- point(one_of(metro));
			location <- point(myself);
			}	
			create species(tourist) number: rnd(1)+1{
			speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
	  		target_loc <- point(one_of(sprinter));
			location <- point(myself);
			luggage_count <- rnd(3)+1;
			}	
		}
	}	
	
	aspect base {
		draw square(2);
	}
}

species walking_area{
	rgb color <- #gray;	
	aspect base {
		draw shape color: color;
	}
}

species people skills:[moving] {
	point target_loc;
	float size <- people_size; 
	image_file icon <- person_icon;
	
	reflex end when: location distance_to target_loc <= 5 * people_size{
		do die;
	}

	reflex move {
		do goto target: target_loc on:(geometry(walking_area));
		if not(self overlaps free_space) {
			location <- ((location closest_points_with free_space)[1]);
		}
	}	
	
	aspect default {
		draw icon size:3 rotate: my heading;
	}
}

species sprinter skills:[moving] control:fsm {
	point target_loc;
	int luggage_capacity;
	image_file icon <- sprinter_icon;
	
	action depart {
		do goto target: target_loc on:the_graph;
	}
	
	state empty initial:true {
		luggage_capacity <- 5;
		target_loc <- any_location_in(one_of(dropoff_area));
		transition to: loading when: (location distance_to one_of(dropoff_area)) <1;
		do depart;
	}
	
	state loading{
		transition to: full when: luggage_capacity < 1;
	}
	
	state full {
		target_loc <- point(one_of(shuttle_spot));////////// This should represent the shuttle_spots
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}
	
	aspect default {
		draw icon size:12 rotate: my heading ;
	}
}

species tourist skills:[moving] control:fsm {
	point target_loc <- (point(one_of(sprinter where(each.state = 'loading'))));
	float speed <- 5 + rnd(1000) / 1000;
	point velocity <- {0,0};
	float size <- people_size; 
	bool dropped_luggage;
	bool knows_where_to_go;
	geometry perceived_area;
	point target;
	int luggage_count;
	bool dropping_now;
	float wating_time;
	int tourist_line;
	image_file icon <- tourist_icon;
	
	 //Stay there and waits for turn. Linear geometry of the queue to define. Waiting time to define
	reflex wait_line when: location distance_to target_loc <= 2 * people_size and dropped_luggage = false{
		dropping_now <- true;
		tourist_line <- tourist count(each.state = 'dropping_luggage');
		wating_time <- wating_time + 0.01;
		if wating_time > (float(tourist_line)+1) { //They should be waiting in line
			write 'Lugagge dropped';	
		}
	}
	
	reflex drop_off when: one_of(dropoff_area) intersects self and dropping_now  and wating_time > (float(tourist_line)+1) {
		target_loc <- point(one_of(shuttle_spot));
		dropped_luggage <- true;
		knows_where_to_go <- true;
		ask one_of(sprinter){
			luggage_capacity <- luggage_capacity - myself.luggage_count;
		}
		luggage_count <- 0;
	}
	
	reflex board when: location = target_loc and dropped_luggage {
		write "bus shuttle taken";
		do die;
	}
	//Reflex to compute the velocity of the agent considering the cohesion factor
	reflex follow_goal  {
		velocity <- velocity + ((target - location) / cohesion_factor_tou);
	}
	
	//If they perceive the drop_off area, they go there. If they don't, they keep looking for it.
	action go {
		if knows_where_to_go  {
			point old_location <- copy(location);
			do goto target: target_loc on: (free_space);
			if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
			}
			velocity <- location - old_location;
		}
	}
	
	action look_for { 
		if (perceived_area intersects target_loc) or (perceived_area intersects one_of(tourist where(each.state = 'found'))) {
			knows_where_to_go <- true;
		} else {
			point old_location <- copy(location);
			do goto target: (any_location_in(perceived_area intersection geometry(walking_area))) on: (free_space);
			if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
			}
		}
	}	
	
	state dropping_luggage{
		enter{
			knows_where_to_go <- true;
			perceived_area <- nil;
		}
		do go;
	}
	
	state found{
		enter{
			knows_where_to_go <- true;
			perceived_area <- nil;
		}
		do go;
		transition to: dropping_luggage when: dropping_now;
	}
	
	state looking_for initial: true {
		do look_for;
		do update_perception;
		transition to: found when: knows_where_to_go or dropping_now;
	}
	
	//Computation of the perceived area
	action update_perception {
		//Perception cone (amplitude 60° and max distance)
		perceived_area <- (cone(heading-30,heading+30) intersection world.shape) intersection circle(perception_distance); 
		
		//Compute the visible area from the perceived area according to the obstacles
		if (perceived_area != nil) {
			perceived_area <- perceived_area masked_by (hbf,precision); //////////////////////////////////////////Error here sometimes but it's ok if you resume simulation
		}
	}
	
	aspect default {
		draw icon size: 3 rotate: my heading;
	}
	aspect perception {
		if (perceived_area != nil) {
			draw perceived_area color: #magenta;
			}
	}
}

experiment "PCM_Simulation" type: gui {
	font regular <- font("Helvetica", 14, # bold);
	output {
		display pie refresh:every(1#mn){
			chart "tourist in the city" type: pie size:{1,1} position: {0,0} {
				data "Oriented tourists" value: nb_tourist_disoriented color: #orange;
				data "Tourists to the shuttles" value: nb_tourist_to_shuttles color: #olive;
			}
		}	
				display series refresh:every(1.5#mn){
			chart "tourist in the city" type: series size:{1,0.5} position: {0,0} {
				data "Disoriented tourists" value: nb_tourist_disoriented color: #orange;
				data "Tourists to the shuttles" value: nb_tourist_to_shuttles color: #olive;
				data "People in the station" value: nb_people_existing color: #black;
			}
		}
		display map type:java2D 
		{
			species hbf aspect:base transparency: 0.75;
			species metro aspect: base ;
			species shuttle_spot aspect: base ;
			species people;
			species dropoff_area aspect: base transparency: 0.85;
			species tourist aspect: default;
			//species tourist aspect: perception transparency:0.97;
			species walking_area aspect:base transparency:0.96 ;
			species sprinter aspect: default;
		
////////////////////User interaction starts here		
			event mouse_move action: move;
			event mouse_up action: click;
			event 'r' action: kill;
			event 'c' action: duplicate;
			graphics "Full target" {
				int size <- length(moved_agents);
				if (size > 0){
					rgb c1 <- rgb(#darkseagreen, 120);
					rgb c2 <- rgb(#firebrick, 120);
					draw zone at: target empty: false border: false color: (can_drop ? c1 : c2);
					draw string(size) at: target + { -30, -30 } font: regular color: # white;
					draw "'r': remove" at: target + { -30, 0 } font: regular color: # white;
					draw "'c': copy" at: target + { -30, 30 } font: regular color: # white;
				}
			}
////////////////////User interaction ends here	
		}
	}
}
