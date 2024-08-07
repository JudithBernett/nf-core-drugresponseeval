include { PREDICT_FULL                  } from '../../../modules/local/predict_full'
include { RANDOMIZATION_SPLIT           } from '../../../modules/local/randomization_split'
include { RANDOMIZATION_TEST            } from '../../../modules/local/randomization_test'
include { ROBUSTNESS_TEST               } from '../../../modules/local/robustness_test'
include { EVALUATE_FINAL                } from '../../../modules/local/evaluate_final'
include { COLLECT_RESULTS               } from '../../../modules/local/collect_results'


workflow MODEL_TESTING {
    take:
    models                      // from input
    best_hpam_per_split         // from RUN_CV: [split_id, test_mode, split_dataset, model_name, best_hpam_combi_X.yaml]
    randomizations              // from input
    cross_study_datasets        // from LOAD_RESPONSE

    main:
    ch_models = channel.from(models)
    if (params.cross_study_datasets == '') {
        cross_study_datasets = Channel.fromPath(['./NONE.csv'])
    }
    ch_tmp = best_hpam_per_split.map{
        split_id, test_mode, path_to_split, model_name, path_to_hpams ->
        return ["dummy", model_name, test_mode, split_id, path_to_split, path_to_hpams]
    }
    ch_tmp2 = cross_study_datasets
                            .collect()
                            .map{it -> ["dummy",  it]}
    ch_predict_final = ch_tmp2.combine(ch_tmp, by: 0)
    // remove dummy from the beginning
    ch_predict_final = ch_predict_final
                            .map{
                                dummy, cross_study_datasets, model_name, test_mode, split_id, path_to_split, path_to_hpams ->
                                return [cross_study_datasets, model_name, test_mode, split_id, path_to_split, path_to_hpams]
                            }

    PREDICT_FULL (
        ch_predict_final,
        params.response_transformation,
        params.path_data
    )
    ch_vis = PREDICT_FULL.out.ch_vis

    if (params.randomization_mode != 'None') {
        ch_randomization = channel.from(randomizations)
        // randomizations only for models, not for baselines
        ch_models_rand = ch_models.combine(ch_randomization)
        RANDOMIZATION_SPLIT (
            ch_models_rand
        )
        ch_best_hpams_per_split_rand = best_hpam_per_split.map {
            split_id, test_mode, path_to_split, model_name, path_to_hpams ->
            return [model_name, test_mode, split_id, path_to_split, path_to_hpams]
        }
        // [model_name, test_mode, split_id, split_dataset, best_hpam_combi_X.yaml, randomization_views]
        ch_randomization = ch_best_hpams_per_split_rand.combine(RANDOMIZATION_SPLIT.out.randomization_test_views, by: 0)
        RANDOMIZATION_TEST (
            ch_randomization,
            params.path_data,
            params.randomization_type,
            params.response_transformation
        )
        ch_vis = ch_vis.concat(RANDOMIZATION_TEST.out.ch_vis)
    }

    if (params.n_trials_robustness > 0) {
        ch_trials_robustness = Channel.from(1..params.n_trials_robustness)
        ch_trials_robustness = ch_models.combine(ch_trials_robustness)

        ch_best_hpams_per_split_rob = best_hpam_per_split.map {
            split_id, test_mode, path_to_split, model_name, path_to_hpams ->
            return [model_name, test_mode, split_id, path_to_split, path_to_hpams]
        }

        // [model_name, test_mode, split_id, split_dataset, best_hpam_combi_X.yaml, robustness_iteration]
        ch_robustness = ch_best_hpams_per_split_rob.combine(ch_trials_robustness, by: 0)
        ROBUSTNESS_TEST (
            ch_robustness,
            params.path_data,
            params.randomization_type,
            params.response_transformation
        )
        ch_vis = ch_vis.concat(ROBUSTNESS_TEST.out.ch_vis)
    }

    EVALUATE_FINAL (
        ch_vis
    )

    ch_collapse = EVALUATE_FINAL.out.ch_individual_results.collect()

    COLLECT_RESULTS (
        ch_collapse
    )
    emit:
    evaluation_results = COLLECT_RESULTS.out.evaluation_results
    evaluation_results_per_drug = COLLECT_RESULTS.out.evaluation_results_per_drug
    evaluation_results_per_cl = COLLECT_RESULTS.out.evaluation_results_per_cl
    true_vs_predicted = COLLECT_RESULTS.out.true_vs_pred
}
