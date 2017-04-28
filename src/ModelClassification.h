
#ifndef MODELCLASSIFICATION_H_
#define MODELCLASSIFICATION_H_

#include "Model.h"

class ModelClassification: public Model {

public:
	ModelClassification();

	ModelClassification(Data* data,
			size_t order,
			std::vector<size_t> features,
			double alpha,
			std::vector<std::ostream*> v_levels);

	virtual ~ModelClassification();

	void fit();

protected:

	// Cases per genotype combination
	std::vector<uint> cases;

	// Controls per genotype combination
	std::vector<uint> controls;

	// Case ratio per genotype combination
	std::vector<double> case_prob_in_cell;

	// Case ratio in all other genotype combinations per genotype combination
	std::vector<double> case_prob_out_cell;

	// Overall case ratio
	double mu;

	// Get counts per cell
	void getCounts();

	// Classify cells
	void classifyCells();

	// Calculate model test statistic
	void calculateModelTestStatistic();

private:
	DISALLOW_COPY_AND_ASSIGN(ModelClassification);

};

#endif /* MODELCLASSIFICATION_H_ */