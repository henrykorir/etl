DELIMITER $$
CREATE CREATE DEFINER=`hkorir`@`%` PROCEDURE `generate_ncd_monthly_report_dataset`(IN query_type varchar(50), IN queue_number int, IN queue_size int, IN cycle_size int, IN start_date varchar(50))
BEGIN

			set @start = now();
			set @table_version = "ncd_monthly_report_dataset_v1.4";
			set @last_date_created = (select max(date_created) from etl.flat_hiv_summary_v15b);

			set @sep = " ## ";
			set @lab_encounter_type = 99999;
			set @death_encounter_type = 31;
            

            create table if not exists ncd_monthly_report_dataset (
				date_created timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP NOT NULL,
                elastic_id bigint,
				endDate date,
                encounter_id int,
				person_id int,
                person_uuid varchar(100),
				birthdate date,
				age double,
				gender varchar(1),
				location_id int,
				location_uuid varchar(100),
				clinic varchar(250),
				encounter_date date,
                visit_this_month tinyint,

				is_hypertensive tinyint,
				htn_state tinyint,

				is_diabetic tinyint,
				dm_state tinyint,

				has_mhd tinyint,
				is_depressive_mhd tinyint,
				is_anxiety_mhd tinyint,
				is_bipolar_and_related_mhd tinyint,
				is_personality_mhd tinyint,
				is_feeding_and_eating_mhd tinyint,
				is_ocd_mhd tinyint,
				
				has_kd tinyint,
				is_ckd tinyint,
				ckd_stage int,

				has_cvd tinyint,
				is_heart_failure_cvd tinyint,
				is_myocardinal_infarction tinyint,

				has_neurological_disorder tinyint,
				has_stroke tinyint,
				is_stroke_haemorrhagic tinyint,
				is_stroke_ischaemic tinyint,

				has_migraine tinyint,
				has_seizure tinyint,
				has_epilepsy tinyint,
				has_convulsive_disorder tinyint,

				has_rheumatologic_disorder tinyint,
				has_arthritis tinyint,
				has_SLE tinyint,


                primary key elastic_id (elastic_id),
				index person_enc_date (person_id, encounter_date),
                index person_report_date (person_id, endDate),
                index endDate_location_id (endDate, location_id),
                index date_created (date_created),
                index status_change (location_id, endDate, status, prev_status)
            );

			if (query_type = "build") then
					select "BUILDING.......................";
					set @queue_table = concat("ncd_monthly_report_dataset_build_queue_",queue_number);                    

					SET @dyn_sql=CONCAT('Create table if not exists ',@queue_table,'(person_id int primary key) (select * from ncd_monthly_report_dataset_build_queue limit ', queue_size, ');'); 
					PREPARE s1 from @dyn_sql; 
					EXECUTE s1; 
					DEALLOCATE PREPARE s1;
                    
					SET @dyn_sql=CONCAT('delete t1 from ncd_monthly_report_dataset_build_queue t1 join ',@queue_table, ' t2 using (person_id)'); 
					PREPARE s1 from @dyn_sql; 
					EXECUTE s1; 
					DEALLOCATE PREPARE s1;  
			end if;

			
            if (query_type = "sync") then
					set @queue_table = "ncd_monthly_report_dataset_sync_queue";                                
                    create table if not exists ncd_monthly_report_dataset_sync_queue (person_id int primary key);
                    
					select @last_update := (select max(date_updated) from etl.flat_log where table_name=@table_version);

					replace into ncd_monthly_report_dataset_sync_queue
                    (select distinct person_id from flat_hiv_summary_v15b where date_created >= @last_update);
            end if;
                        

			SET @num_ids := 0;
			SET @dyn_sql=CONCAT('select count(*) into @num_ids from ',@queue_table,';'); 
			PREPARE s1 from @dyn_sql; 
			EXECUTE s1; 
			DEALLOCATE PREPARE s1;          
            
            
            SET @person_ids_count = 0;
			SET @dyn_sql=CONCAT('select count(*) into @person_ids_count from ',@queue_table); 
			PREPARE s1 from @dyn_sql; 
			EXECUTE s1; 
			DEALLOCATE PREPARE s1;  
            
            
            SET @dyn_sql=CONCAT('delete t1 from ncd_monthly_report_dataset t1 join ',@queue_table,' t2 using (person_id);'); 
			PREPARE s1 from @dyn_sql; 
			EXECUTE s1; 
			DEALLOCATE PREPARE s1;  
            
            set @total_time=0;
			set @cycle_number = 0;
                    
			while @person_ids_count > 0 do
			
				set @loop_start_time = now();                        

				drop temporary table if exists ncd_monthly_report_dataset_build_queue__0;
                create temporary table ncd_monthly_report_dataset_build_queue__0 (person_id int primary key);                

                SET @dyn_sql=CONCAT('insert into ncd_monthly_report_dataset_build_queue__0 (select * from ',@queue_table,' limit ',cycle_size,');'); 
				PREPARE s1 from @dyn_sql; 
				EXECUTE s1; 
				DEALLOCATE PREPARE s1;
                
                
                set @age =null;
                set @status = null;
                
                drop temporary table if exists ncd_monthly_report_dataset_0;
				create temporary table ncd_monthly_report_dataset_0
				(select 
					concat(date_format(endDate,"%Y%m"),person_id) as elastic_id,
					endDate,
                    encounter_id,
					person_id,
                    t3.uuid as person_uuid,
					date(birthdate) as birthdate,
					case
						when timestampdiff(year,birthdate,endDate) > 0 then @age := round(timestampdiff(year,birthdate,endDate),0)
						else @age :=round(timestampdiff(month,birthdate,endDate)/12,2)
					end as age,
					t3.gender,
					date(encounter_datetime) as encounter_date, 
                    
                    if(encounter_datetime between date_format(endDate,"%Y-%m-01")  and endDate,1,0) as visit_this_month,
                    
					case
						when arv_first_regimen_location_id != 9999 
							and arv_first_regimen_start_date between date_format(endDate,"%Y-%m-01")  and endDate then arv_first_regimen_location_id
                        else location_id
                    end as location_id,                  
                    
                    
					encounter_type,
					
					case
					    when htn_status = 7285 or htn_status = 7286 then 1
						when (comorbidities regexp '[[:<:]]903[[:>:]]') then 1
						when (prev_hbp_findings regexp '[[:<:]]1065[[:>:]]') then 1
						when (htn_meds is not null) then 1
						when (problems regexp '[[:<:]]903[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]903[[:>:]]') then 1
						else null
					end as is_hypertensive,

					case
						when ((sbp < 130) and (dbp < 80)) then 1 
						when ((sbp >= 130) and (dbp >= 80)) then 2
						when ((sbp is null) or (dbp is null)) then 3
						else NULL
					end as htn_state,

					case
					    when dm_status = 7281 or dm_status = 7282 then 1
						when (comorbidities regexp '[[:<:]]175[[:>:]]') then 1
						when (dm_meds is not null) then 1
						when (problems regexp '[[:<:]]9324|175[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]175[[:>:]]') then 1
						else null
					end as is_diabetic,

					case
						when (hb_a1c >= 7 and hb_a1c <= 8) then 1 
						when (hb_a1c < 7 and hb_a1c > 8) then 2
						when (hb_a1c is null) or (hb_a1c is null) then 3
						else null
					end as dm_state,

					case
						when (comorbidities regexp '[[:<:]]10860[[:>:]]') then 1
						when (indicated_mhd_tx is not null) then 1
						when (has_past_mhd_tx = '1065') then 1
						when (review_of_med_history regexp '[[:<:]]77|207[[:>:]]') then 1
						when (eligible_for_depression_care = '1065') then 1
						when (mood_disorder is not null) then 1
						when (anxiety_condition is not null) then 1
						when (psychiatric_exam_findings is not null) then 1
						else null
					end as has_mhd,

					case
						when (eligible_for_depression_care = '1065') then 1
						when (mood_disorder regexp '[[:<:]]11278[[:>:]]') then 1
						when (indicated_mhd_tx regexp '[[:<:]]207[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]207[[:>:]]') then 1
						when (psychiatric_exam_findings regexp '[[:<:]]207[[:>:]]') then 1
						else null
					end as is_depressive_mhd,

					case
						when (anxiety_condition is not null) then 1
						when (indicated_mhd_tx regexp '[[:<:]]1443[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]207[[:>:]]') then 1
						when (psychiatric_exam_findings regexp '[[:<:]]1443[[:>:]]') then 1
						else null
					end as is_anxiety_mhd,

					case
						when (mood_disorder regexp '[[:<:]]7763[[:>:]]') then 1
						when (indicated_mhd_tx regexp '[[:<:]]7763[[:>:]]') then 1
						else null
					end as is_bipolar_and_related_mhd,

					case
						when (mood_disorder regexp '[[:<:]]7763[[:>:]]') then 1
						when (indicated_mhd_tx regexp '[[:<:]]11281[[:>:]]') then 1
						when (problems regexp '[[:<:]]467[[:>:]]') then 1
						else null
					end as is_personality_mhd,

					null as is_feeding_and_eating_mhd,

					null as is_ocd_mhd,

					case
						when (comorbidities regexp '[[:<:]]77[[:>:]]') then 1
						when (kidney_disease = '[[:<:]]1065[[:>:]]') then 1
						when (problems regexp '[[:<:]]8078|11684[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]6033|8078[[:>:]]') then 1
						else null
					end as has_kd,

					case
						when (problems regexp '[[:<:]]8078[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]8078[[:>:]]') then 1
						when (ckd_staging is not null) then 1
						else null
					end as is_ckd,

					ckd_staging as ckd_stage,

					case
						when (cardiovascular_disorder is not null) then 1
						when (comorbidities regexp '[[:<:]]7971[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]7971|6237[[:>:]]') then 1
						else null
					end as has_cvd,

					case
						when (cardiovascular_disorder regexp '[[:<:]]1456[[:>:]]') then 1
						when (indicated_mhd_tx regexp '[[:<:]]1456[[:>:]]') then 1
						when (review_of_med_history regexp '[[:7971') then 1
						else null
					end as is_heart_failure_cvd,

					case
						when (cardiovascular_disorder regexp '[[:<:]]1535[[:>:]]') then 1
						else null
					end as is_myocardinal_infarction,

					case
						when (neurological_disease is not null) then 1
						when (indicated_mhd_tx regexp '[[:<:]]1456[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]7971[[:>:]]') then 1
						else null
					end as has_neurological_disorder,

					case
						when (cardiovascular_disorder regexp '[[:<:]]1878[[:>:]]') then 1
						when (indicated_mhd_tx regexp '[[:<:]]1456[[:>:]]') then 1
						when (review_of_med_history regexp '[[:<:]]7971[[:>:]]') then 1
						else null
					end as has_stroke,

					null as is_stroke_haemorrhagic

					null as is_stroke_ischaemic,

					case
						when (problems regexp '[[:<:]]1477[[:>:]]') then 1
						when (neurological_disease regexp '[[:<:]]1477[[:>:]]') then 1
						else null
					end as has_migraine,

					case
						when (problems regexp '[[:<:]]206[[:>:]]') then 1
						when (neurological_disease regexp '[[:<:]]206[[:>:]]') then 1
						when (convulsive_disorder regexp '[[:<:]]206[[:>:]]') then 1
						else null
					end as has_seizure,

					case
						when (problems regexp '[[:<:]]155|11687[[:>:]]') then 1
						when (neurological_disease regexp '[[:<:]]155[[:>:]]') then 1
						when (convulsive_disorder regexp '[[:<:]]155[[:>:]]') then 1
						when (indicated_mhd_tx regexp '[[:<:]]155[[:>:]]') then 1
						else null
					end as has_epilepsy,

					case
						when (neurological_disease regexp '[[:<:]]10806[[:>:]]') then 1
						when (convulsive_disorder regexp '[[:<:]]155|10806[[:>:]]') then 1
						else null
					end as has_convulsive_disorder,

					case
						when (rheumatologic_disorder is not null) then 1
						when (comorbidities regexp '[[:<:]]12293[[:>:]]') then 1
						else null
					end as has_rheumatologic_disorder,

					case
						when (rheumatologic_disorder regexp '[[:<:]]116[[:>:]]') then 1
						else null
					end as has_arthritis,

					case
						when (rheumatologic_disorder regexp '[[:<:]]12292[[:>:]]') then 1
						else null
					end as has_SLE

					from etl.dates t1
					join etl.flat_ncd t2 
					join amrs.person t3 using (person_id)
					join etl.ncd_monthly_report_dataset_build_queue__0 t5 using (person_id)
                    
					where  
                            t2.encounter_datetime < date_add(endDate, interval 1 day)
							and (t2.next_clinical_datetime_cdm is null or t2.next_clinical_datetime_cdm >= date_add(t1.endDate, interval 1 day) )
							and t2.is_clinical_encounter=1 
							and t1.endDate between start_date and date_add(now(),interval 2 year)
					order by person_id, endDate
				);
                
				set @prev_id = null;
				set @cur_id = null;
                set @prev_location_id = null;
                set @cur_location_id = null;

				drop temporary table if exists ncd_monthly_report_dataset_1;
				create temporary table ncd_monthly_report_dataset_1
				(select
					*,
					@prev_id := @cur_id as prev_id,
					@cur_id := person_id as cur_id,

					case
						when @prev_id=@cur_id then @prev_location_id := @cur_location_id
                        else @prev_location_id := null
					end as next_location_id,
                    
                    @cur_location_id := location_id as cur_location_id,

					from ncd_monthly_report_dataset_0
					order by person_id, endDate desc
				);

				alter table ncd_monthly_report_dataset_1 drop prev_id, drop cur_id;

				set @prev_id = null;
				set @cur_id = null;
                set @cur_location_id = null;
                set @prev_location_id = null;
				drop temporary table if exists hiv_monthly_report_dataset_2;
				create temporary table hiv_monthly_report_dataset_2
				(select
					*,
					@prev_id := @cur_id as prev_id,
					@cur_id := person_id as cur_id,
                    
                    case
						when @prev_id=@cur_id then @prev_location_id := @cur_location_id
                        else @prev_location_id := null
					end as prev_location_id,
                    
                    @cur_location_id := location_id as cur_location_id
						
					from ncd_monthly_report_dataset_1
					order by person_id, endDate
				);
                                
                select now();
				select count(*) as num_rows_to_be_inserted from ncd_monthly_report_dataset_2;
	
				#add data to table									  
				replace into ncd_monthly_report_dataset											  
				(select
					null, #date_created will be automatically set or updated
				elastic_id,
				endDate,
                encounter_id,
				person_id,
                person_uuid,
				birthdate,
				age,
				gender,
				location_id,
				location_uuid,
				t2.name as clinic
				encounter_date,
                visit_this_month,

				is_hypertensive,
				htn_state,

				is_diabetic,
				dm_state,

				has_mhd,
				is_depressive_mhd,
				is_anxiety_mhd,
				is_bipolar_and_related_mhd,
				is_personality_mhd,
				is_feeding_and_eating_mhd,
				is_ocd_mhd,
				
				has_kd,
				is_ckd,
				ckd_stage,

				has_cvd,
				is_heart_failure_cvd,
				is_myocardinal_infarction,

				has_neurological_disorder,
				has_stroke,
				is_stroke_haemorrhagic,
				is_stroke_ischaemic,

				has_migraine,
				has_seizure,
				has_epilepsy,
				has_convulsive_disorder,

				has_rheumatologic_disorder,
				has_arthritis,
				has_SLE

					from ncd_monthly_report_dataset_2 t1
                    join amrs.location t2 using (location_id)
				);
                

				SET @dyn_sql=CONCAT('delete t1 from ',@queue_table,' t1 join ncd_monthly_report_dataset_build_queue__0 t2 using (person_id);'); 
				PREPARE s1 from @dyn_sql; 
				EXECUTE s1; 
				DEALLOCATE PREPARE s1;  
				                        
				SET @dyn_sql=CONCAT('select count(*) into @person_ids_count from ',@queue_table,';'); 
				PREPARE s1 from @dyn_sql; 
				EXECUTE s1; 
				DEALLOCATE PREPARE s1;  
                
                
				set @cycle_length = timestampdiff(second,@loop_start_time,now());
				                   
				set @total_time = @total_time + @cycle_length;
				set @cycle_number = @cycle_number + 1;
				
				set @remaining_time = ceil((@total_time / @cycle_number) * ceil(@person_ids_count / cycle_size) / 60);
                
                select @num_in_nmrd as num_in_nmrd,
					@person_ids_count as num_remaining, 
					@cycle_length as 'Cycle time (s)', 
                    ceil(@person_ids_count / cycle_size) as remaining_cycles, 
                    @remaining_time as 'Est time remaining (min)';


			end while;

			if(query_type = "build") then
					SET @dyn_sql=CONCAT('drop table ',@queue_table,';'); 
					PREPARE s1 from @dyn_sql; 
					EXECUTE s1; 
					DEALLOCATE PREPARE s1;  
			end if;            

			set @end = now();
            # not sure why we need last date_created, Ive replaced this with @start
			insert into etl.flat_log values (@start,@last_date_created,@table_version,timestampdiff(second,@start,@end));
			select concat(@table_version," : Time to complete: ",timestampdiff(minute, @start, @end)," minutes");

        END$$
DELIMITER ;
