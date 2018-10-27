/obj/machinery/sleeper
	name = "sleeper"
	desc = "A fancy bed with built-in injectors, a dialysis machine, and a limited health scanner."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "sleeper_0"
	density = 1
	anchored = 1
	clicksound = 'sound/machines/buttonbeep.ogg'
	clickvol = 30
	var/mob/living/carbon/human/occupant = null
	var/list/available_chemicals = list("Inaprovaline" = /datum/reagent/inaprovaline, "Soporific" = /datum/reagent/soporific, "Paracetamol" = /datum/reagent/paracetamol, "Dylovene" = /datum/reagent/dylovene, "Dexalin" = /datum/reagent/dexalin)
	var/obj/item/weapon/reagent_containers/glass/beaker = null
	var/filtering = 0
	var/pump
	var/list/stasis_settings = list(1, 2, 5)
	var/stasis = 1

	var/efficiency
	var/initial_bin_rating = 1
	var/min_health = 25

	use_power = 1
	idle_power_usage = 15
	active_power_usage = 200 //builtin health analyzer, dialysis machine, injectors.

/obj/machinery/sleeper/Initialize()
	. = ..()
	if(!map_storage_loaded)
		beaker = new /obj/item/weapon/reagent_containers/glass/beaker/large(src)
	update_icon()

/obj/machinery/sleeper/Process()
	if(stat & (NOPOWER|BROKEN))
		return

	if(filtering > 0)
		if(beaker)
			if(beaker.reagents.total_volume < beaker.reagents.maximum_volume)
				var/pumped = 0
				for(var/datum/reagent/x in occupant.reagents.reagent_list)
					occupant.reagents.trans_to_obj(beaker, 3)
					pumped++
				if(ishuman(occupant))
					occupant.vessel.trans_to_obj(beaker, pumped + 1)
		else
			toggle_filter()
	if(pump > 0)
		if(beaker && istype(occupant))
			if(beaker.reagents.total_volume < beaker.reagents.maximum_volume)
				for(var/datum/reagent/x in occupant.ingested.reagent_list)
					occupant.ingested.trans_to_obj(beaker, 3)
		else
			toggle_pump()

	if(iscarbon(occupant) && stasis > 1)
		occupant.SetStasis(stasis)

/obj/machinery/sleeper/update_icon()
	icon_state = "sleeper_[occupant ? "1" : "0"]"

/obj/machinery/sleeper/attack_hand(var/mob/user)
	if(..())
		return 1

	ui_interact(user)

/obj/machinery/sleeper/ui_interact(var/mob/user, var/ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1, var/datum/topic_state/state = GLOB.outside_state)
	var/data[0]

	data["power"] = stat & (NOPOWER|BROKEN) ? 0 : 1

	var/list/reagents = list()
	for(var/T in available_chemicals)
		var/list/reagent = list()
		reagent["name"] = T
		if(occupant && occupant.reagents)
			reagent["amount"] = occupant.reagents.get_reagent_amount(T)
		reagents += list(reagent)
	data["reagents"] = reagents.Copy()

	if(occupant)
		var/scan = medical_scan_results(occupant)
		scan = replacetext(scan,"'notice'","'white'")
		scan = replacetext(scan,"'warning'","'average'")
		scan = replacetext(scan,"'danger'","'bad'")
		data["occupant"] =scan
	else
		data["occupant"] = 0
	if(beaker)
		data["beaker"] = beaker.reagents.get_free_space()
	else
		data["beaker"] = -1
	data["filtering"] = filtering
	data["pump"] = pump
	data["stasis"] = stasis

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "sleeper.tmpl", "Sleeper UI", 600, 600, state = state)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(1)

/obj/machinery/sleeper/CanUseTopic(user)
	if(user == occupant)
		to_chat(usr, "<span class='warning'>You can't reach the controls from the inside.</span>")
		return STATUS_CLOSE
	return ..()

/obj/machinery/sleeper/OnTopic(user, href_list)
	add_fingerprint(user)
	if(href_list["eject"])
		go_out()
		return TOPIC_REFRESH
	if(href_list["beaker"])
		remove_beaker()
		return TOPIC_REFRESH
	if(href_list["filter"])
		if(filtering != text2num(href_list["filter"]))
			toggle_filter()
			return TOPIC_REFRESH
	if(href_list["pump"])
		if(filtering != text2num(href_list["pump"]))
			toggle_pump()
			return TOPIC_REFRESH
	if(href_list["chemical"] && href_list["amount"])
		if(occupant && occupant.stat != DEAD)
			if(href_list["chemical"] in available_chemicals) // Your hacks are bad and you should feel bad
				inject_chemical(usr, href_list["chemical"], text2num(href_list["amount"]))
				return TOPIC_REFRESH
	if(href_list["stasis"])
		var/nstasis = text2num(href_list["stasis"])
		if(stasis != nstasis && nstasis in stasis_settings)
			stasis = text2num(href_list["stasis"])
			return TOPIC_REFRESH

/obj/machinery/sleeper/attack_ai(var/mob/user)
	return attack_hand(user)

/obj/machinery/sleeper/attackby(var/obj/item/I, var/mob/user)
	add_fingerprint(user)
	if(istype(I, /obj/item/weapon/reagent_containers/glass))
		if(!beaker)
			beaker = I
			user.drop_item()
			I.forceMove(src)
			user.visible_message("<span class='notice'>\The [user] adds \a [I] to \the [src].</span>", "<span class='notice'>You add \a [I] to \the [src].</span>")
		else
			to_chat(user, "<span class='warning'>\The [src] has a beaker already.</span>")
		return

	if(istype(I, /obj/item/grab/normal))
		var/obj/item/grab/normal/G = I
		if (!ismob(G.affecting))
			return
		if(go_in(G.affecting, user))
			qdel(G)

/obj/machinery/sleeper/MouseDrop_T(var/mob/target, var/mob/user)
	if(!CanMouseDrop(target, user))
		return
	if(!istype(target))
		return
	go_in(target, user)

/obj/machinery/sleeper/relaymove(var/mob/user)
	..()
	go_out()

/obj/machinery/sleeper/emp_act(var/severity)
	if(filtering)
		toggle_filter()

	if(stat & (BROKEN|NOPOWER))
		..(severity)
		return

	if(occupant)
		go_out()

	..(severity)
/obj/machinery/sleeper/proc/toggle_filter()
	if(!occupant || !beaker)
		filtering = 0
		return
	to_chat(occupant, "<span class='warning'>You feel like your blood is being sucked away.</span>")
	filtering = !filtering

/obj/machinery/sleeper/proc/toggle_pump()
	if(!occupant || !beaker)
		pump = 0
		return
	to_chat(occupant, "<span class='warning'>You feel a tube jammed down your throat.</span>")
	pump = !pump

/obj/machinery/sleeper/proc/go_in(var/mob/M, var/mob/user)
	if(!M)
		return FALSE
	if(stat & (BROKEN|NOPOWER))
		return FALSE
	if(occupant)
		to_chat(user, "<span class='warning'>\The [src] is already occupied.</span>")
		return FALSE

	if(M == user)
		visible_message("\The [user] starts climbing into \the [src].")
	else
		visible_message("\The [user] starts putting [M] into \the [src].")

	if(do_after(user, 20, M))
		if(occupant)
			to_chat(user, "<span class='warning'>\The [src] is already occupied.</span>")
			return FALSE
		if (M.buckled)
			M.buckled.user_unbuckle_mob(user)
			if (M.buckled)
				return FALSE
		M.stop_pulling()
		if(M.client)
			M.client.perspective = EYE_PERSPECTIVE
			M.client.eye = src
		M.forceMove(src)
		update_use_power(2)
		occupant = M
		update_icon()
		return TRUE
	return FALSE

/obj/machinery/sleeper/proc/go_out()
	if(!occupant)
		return
	if(occupant.client)
		occupant.client.eye = occupant.client.mob
		occupant.client.perspective = MOB_PERSPECTIVE
	occupant.dropInto(loc)
	occupant = null
	for(var/obj/O in (contents - component_parts)) // In case an object was dropped inside or something. Excludes the beaker and component parts.
		if(O == beaker)
			continue
		O.dropInto(loc)
	update_use_power(1)
	update_icon()
	toggle_filter()

/obj/machinery/sleeper/proc/remove_beaker()
	if(beaker)
		beaker.dropInto(loc)
		beaker = null
		toggle_filter()
		toggle_pump()

/obj/machinery/sleeper/proc/inject_chemical(var/mob/living/user, var/chemical_name, var/amount)
	if(stat & (BROKEN|NOPOWER))
		return

	var/chemical_type = available_chemicals[chemical_name]
	if(beaker.reagents.get_reagent_amount(chemical_type) > 0)
		if(beaker.reagents.get_reagent_amount(chemical_type) < amount)
			amount = beaker.reagents.get_reagent_amount(chemical_type)
		if(occupant && occupant.reagents)
			if(occupant.reagents.get_reagent_amount(chemical_type) + amount <= 20)
				use_power(amount * CHEM_SYNTH_ENERGY)
				occupant.reagents.add_reagent(chemical_type, amount)
				to_chat(user, "Occupant now has [occupant.reagents.get_reagent_amount(chemical_type)] unit\s of [chemical_name] in their bloodstream.")
			else
				to_chat(user, "The subject has too many chemicals.")
		else
			to_chat(user, "There's no suitable occupant in \the [src].")
	else
		to_chat(user, "There is no [chemical_name] in the beaker")


/obj/machinery/sleeper/New()
	..()
	component_parts = list()
	component_parts += new /obj/item/weapon/circuitboard/sleeper(src)

	// Customizable bin rating, used by the labor camp to stop people filling themselves with chemicals and escaping.
	var/obj/item/weapon/stock_parts/matter_bin/B = new(src)
	B.rating = initial_bin_rating
	component_parts += B

	component_parts += new /obj/item/weapon/stock_parts/manipulator(src)
	component_parts += new /obj/item/weapon/stock_parts/console_screen(src)
	component_parts += new /obj/item/weapon/stock_parts/console_screen(src)
	component_parts += new /obj/item/stack/cable_coil(src, 1)
	RefreshParts()


/obj/machinery/sleeper/upgraded/New()
	..()
	component_parts = list()
	component_parts += new /obj/item/weapon/circuitboard/sleeper(src)
	component_parts += new /obj/item/weapon/stock_parts/matter_bin/super(src)
	component_parts += new /obj/item/weapon/stock_parts/manipulator/pico(src)
	component_parts += new /obj/item/weapon/stock_parts/console_screen(src)
	component_parts += new /obj/item/weapon/stock_parts/console_screen(src)
	component_parts += new /obj/item/stack/cable_coil(src, 1)
	RefreshParts()

/obj/machinery/sleeper/RefreshParts()
	var/E
	var/I
	for(var/obj/item/weapon/stock_parts/matter_bin/B in component_parts)
		E += B.rating
	for(var/obj/item/weapon/stock_parts/manipulator/M in component_parts)
		I += M.rating

	efficiency = E
	min_health = -E * 25


/obj/machinery/sleeper/attackby(var/obj/item/O as obj, var/mob/user as mob)

	if(default_deconstruction_screwdriver(user, O))
		updateUsrDialog()
		return
	if(default_deconstruction_crowbar(user, O))
		return
	if(default_part_replacement(user, O))
		return
	return ..()